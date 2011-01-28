require 'cgi'
require 'nokogiri'
require './dsts.rb'

class NilClass
  def length
    0
  end
end

# How many columns to use for the strings' textareas
TA_COLS = 80

class AndroidTranslationHelper
  def initialize()
    @en_strings_xml = File.new('strings.xml').read
    cache_strings()
  end

  def call(env)
    @env = env
    @gecko = @env['HTTP_USER_AGENT'].match(/(?<!like )gecko/i)

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
    elsif m == "POST" and @path[0] == "post_strings" then
      post_strings()
    elsif m == "GET" and @path[0] == "upload_strings" then
      show_upload_form()
    elsif m == "GET" and @path[0] == "show_cached_strings" then
      show_cached_strings()
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

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def home()
    p = XhtmlPage.new
    p.title = "Android Translation Helper"

    p.add "<h2>#{p.title}</h2>\n"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def show_upload_form
    p = XhtmlPage.new

    p.add %Q{<form method="post" action="/ath/post_strings" enctype="multipart/form-data">}
    p.add %Q{<input type="file" name="file">}
    p.add %Q{<input type="submit" value="Submit" /></form>}

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def post_strings
    req = Rack::Request.new(@env)
    filename = req.params['file'][:filename]
    content_type = req.params['file'][:type]
    file_contents = req.params['file'][:tempfile].read()

    @en_strings_xml = file_contents
    cache_strings()
    File.new('strings.xml', 'w').write(file_contents)

    if content_type != 'text/xml' and content_type != 'application/xml' then
      p = XhtmlPage.new
      p.add "<p>Sorry, that file is <code>#{content_type}</code>, not <code>text/xml</code></p>"
      return [200, {"Content-Type" => "text/html"}, p.generate]
    end

    [302, {'Location' => '/ath/show_cached_strings'}, '302 Found']
  end

  def show_cached_strings
    p = XhtmlPage.new

    add_string = lambda do |name, string|
      p.add "<hr><b>#{name}</b><br />\n"

      cols = 80
      rows = string.length / cols + 1

      rows += (string.count("\n") + string.match(/\n\n/).length) / 2

      if @gecko then
        gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
      else
        gecko_hack = ""
      end

      p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>}
    end

    @strings.each do |name, string|
      add_string.call(name, string)
    end

    @str_ars.each do |name, a|
      i = 0
      a.each do |string|
        add_string.call(name + "[#{i}]", string)
        i += 1
      end
    end

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def cache_strings
    @strings = Hash.new()
    @str_ars = Hash.new()

    doc = Nokogiri::XML(@en_strings_xml)

    doc.xpath('//string').each do |s|
      string = String.new
      c = s.child
      while c != nil do
        string += c.to_s
        c = c.next
      end

      s2 = string.dup
      #string = s2.gsub(/(\s+)/, " ").strip
      string = s2.gsub(/(\s+)/, " ").gsub(/\\n\ \\n/, "\\n\\n").gsub(/\\n/, "\\n\n").strip

      @strings[s.attr('name')] = string
    end

    doc.xpath('//string-array').each do |sa|
      @str_ars[sa.attr('name')] = Array.new()

      i = 0
      sa.element_children.each do |item|
        string = String.new
        c = item.child
        while c != nil do
          string += c.to_s
          c = c.next
        end

        @str_ars[sa.attr('name')][i] = string
        i += 1
      end
    end
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
