require 'rubygems'
require 'rack'
require 'cgi'
require 'dsts'
require 'fcgi.rb'
require 'nokogiri'
require 'rexml/document'

class AndroidTranslationHelper
  def call(env)
    @t = Time.now

    @env = env

    # REQUEST_URI is still encoded; split before decoding to allow encoded slashes
    @path = env['REQUEST_URI'].split('/')

    # REQUEST_URI starts with /ath/, so delete blank first element and second ('ath') element
    2.times { @path.delete_at(0) }

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
    elsif m == "GET" and @path[0] == "__FILE__" then
      [200, {"Content-Type" => "text/plain"}, File.new(__FILE__).read]
    elsif @path[0] == "strings" then
      if m == "POST" then
        post_strings_n()
      else
        show_upload_form()
      end
    else
      default()
    end
  end

  def default()
    p = XhtmlPage.new
    path = @path.join(', ')

    p.title = "#{path}"
    p.add "<p><b>Path:</b> #{path}</p>"
    p.add "<div>" + dump_env() + "</div>"

    p.title = "#{Time.now - @t} seconds"
    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def home()
    p = XhtmlPage.new
    p.title = "Android Translation Helper"

    p.add "<h2>#{p.title}</h2>\n"

    p.title = "#{Time.now - @t} seconds"
    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def keepalive
    p = XhtmlPage.new
    p.title = "keepalive"

    p.add "<p>keepalive</p>"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def show_upload_form
    p = XhtmlPage.new

    p.add %Q{<form method="post" enctype="multipart/form-data">}
    p.add %Q{<input type="file" name="file">}
    p.add %Q{<input type="submit" value="Submit" /></form>}

    p.title = "#{Time.now - @t} seconds"
    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def post_strings_r
    p = XhtmlPage.new

    req = Rack::Request.new(@env)
    filename = req.params['file'][:filename]
    content_type = req.params['file'][:type]
    file_contents = req.params['file'][:tempfile].read()

    if content_type != 'text/xml' then
      p.add "<p>Sorry, that file is <code>#{content_type}</code>, not <code>text/xml</code></p>"
      return [200, {"Content-Type" => "text/html"}, p.generate]
    end

    #require 'rexml/document'
    doc = REXML::Document.new(file_contents)
    doc.elements.each('//string') do |s|
      p.add "<hr><b>#{s.attributes['name']}</b><br />\n"

      string = String.new
      s.each_child do |c|
        string += c.to_s
      end

      p.add %Q{<textarea cols="80" rows="#{string.count("\n")}">#{string}</textarea>}
    end

    p.title = "#{Time.now - @t} seconds"
    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def post_strings_n
    p = XhtmlPage.new

    req = Rack::Request.new(@env)
    filename = req.params['file'][:filename]
    content_type = req.params['file'][:type]
    file_contents = req.params['file'][:tempfile].read()

    if content_type != 'text/xml' then
      p.add "<p>Sorry, that file is <code>#{content_type}</code>, not <code>text/xml</code></p>"
      return [200, {"Content-Type" => "text/html"}, p.generate]
    end

    #require 'nokogiri'
    doc = Nokogiri::XML(file_contents)
    doc.xpath('//string').each do |s|
      p.add "<hr><b>#{s.attr('name')}</b><br />\n"

      string = String.new
      c = s.child
      while c != nil do
        string += c.to_s
        c = c.next
      end

      p.add %Q{<textarea cols="80" rows="#{string.count("\n")}">#{string}</textarea>}
    end

    p.title = "#{Time.now - @t} seconds"
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

Rack::Handler::FastCGI.run(AndroidTranslationHelper.new, :File => '/tmp/ath.sock')
