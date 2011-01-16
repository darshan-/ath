require 'appengine-rack'
require 'appengine-apis/users'
require 'cgi'
require 'dm-core'
require 'dsts'
require 'nokogiri'

DataMapper.setup(:default, "appengine://auto")

class Greeting
  include DataMapper::Resource
  property :id, Serial # required for DataMapper
  property :author, User # <-- NOTE: This stores the whole object, not the id
  property :content, Text
  property :date, Time, :default => lambda { |r, p| Time.now } # must be a Proc  
end

class XMLFile
  include DataMapper::Resource
  property :id, Serial # required for DataMapper
  property :name, String
  property :body, Text
end

class AndroidTranslationHelper
  def call(env)
    @env = env

    # REQUEST_URI is still encoded; split before decoding to allow encoded slashes
    @path = env['REQUEST_URI'].split('/')

    # REQUEST_URI starts with '/', so delete blank first element
    @path.delete_at(0)

    @path.each_index do |i|
      @path[i]= CGI.unescape(@path[i])
    end

    route()
  end

  def route
    m = @env['REQUEST_METHOD']

    if m == "GET" and @path.empty? then
      home()
    elsif m == "GET" and @path[0] == "keepalive" then
      keepalive()
    elsif @path[0] == "greetings" then
      if m == "POST" then
        post_greeting()
      else
        show_greetings()
      end
    else
      default()
    end
  end

  def default
    p = XhtmlPage.new
    path = @path.join(', ')

    p.title = "#{path}"
    p.add "<p><b>Path:</b> #{path}</p>"
    p.add "<div>" + dump_env() + "</div>"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def home
    p = XhtmlPage.new
    p.title = "Android Translation Helper"

    p.add "<h2>#{p.title}</h2>\n"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def keepalive
    p = XhtmlPage.new
    p.title = "keepalive"

    p.add "<p>keepalive</p>"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def show_greetings
    p = XhtmlPage.new
    p.title = "Greetings"

    p.add %Q{<form method="post" enctype="multipart/form-data">}
    p.add %Q{<input type="file" name="file">}
    p.add %Q{<input type="submit" value="Submit" /></form>}

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def post_greeting
    return post_greeting3
    p = XhtmlPage.new

    p.add "<pre>" + CGI.escapeHTML(@env['rack.input'].read()) + "</pre>"

    p.add "<div>" + dump_env() + "</div>"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def post_greeting2
    p = XhtmlPage.new

    req = Rack::Request.new(@env)
    filename = req.params['file'][:filename]
    file_contents = req.params['file'][:tempfile].read()

    p.add filename + ":"
    p.add "<pre>" + CGI.escapeHTML(file_contents) + "</pre>"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def post_greeting3
    p = XhtmlPage.new

    req = Rack::Request.new(@env)
    filename = req.params['file'][:filename]
    content_type = req.params['file'][:type]
    file_contents = req.params['file'][:tempfile].read()

    if content_type != 'text/xml' then
      p.add "<p>Sorry, that file is <code>#{content_type}</code>, not <code>text/xml</code></p>"
      return [200, {"Content-Type" => "text/html"}, p.generate]
    end

    doc = Nokogiri::XML(file_contents)
    strings = doc.xpath('//string')

    strings.each do |s|
      p.add "<hr><b>#{s.attr('name')}</b><br />\n"

      string = String.new
      c = s.child
      while c != nil do
        string += c.to_s
        c = c.next
      end

      p.add %Q{<textarea cols="80" rows="#{string.count("\n")}">#{string}</textarea>}
    end

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def dump_env
    s = String.new

    s << "<hr />\n<p><i>" + Time.new.to_s + "</i></p>\n"
    s << "<br />\nEnvironment:<br />\n"
    @env.each do |key, value|
      s << "* #{key} =&gt; #{CGI.escapeHTML(value.to_s)}<br />\n"
    end

    s
  end
end

run AndroidTranslationHelper.new
