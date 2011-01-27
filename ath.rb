require 'rubygems'
#require 'fcgi'
require 'rack'
require 'cgi'
require 'nokogiri'
load 'dsts.rb'

class AndroidTranslationHelper
  def initialize()
    @en_strings_xml = File.new('strings.xml').read
    cache_strings()
  end

  def call(env)
    @t = Time.now

    @env = env
    @gecko =  @env['HTTP_USER_AGENT'].match(/gecko/i) &&   # No look-behind in ruby 1.8 :(
             !@env['HTTP_USER_AGENT'].match(/like gecko/i) #  so we need two regexps

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
        post_strings()
      else
        show_upload_form()
      end
    elsif @path[0] == "show_strings" then
      show_strings()
    elsif @path[0] == "show_cached_strings" then
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

  def post_strings
    p = XhtmlPage.new

    req = Rack::Request.new(@env)
    filename = req.params['file'][:filename]
    content_type = req.params['file'][:type]
    file_contents = req.params['file'][:tempfile].read()

    if content_type != 'text/xml' and content_type != 'application/xml' then
      p.add "<p>Sorry, that file is <code>#{content_type}</code>, not <code>text/xml</code></p>"
      return [200, {"Content-Type" => "text/html"}, p.generate]
    end

    doc = Nokogiri::XML(file_contents)

    doc.xpath('//string').each do |s|
      p.add "<hr><b>#{s.attr('name')}</b><br />\n"

      string = String.new
      c = s.child
      while c != nil do
        string += c.to_s
        c = c.next
      end

      s2 = string.dup
      string = s2.gsub(/(\s+)/, " ").strip

      cols = 80
      rows = string.length / cols + 1

      if @gecko then
        gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
      else
        gecko_hack = ""
      end

      p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>}
    end

    doc.xpath('//string-array').each do |sa|
      i = 0
      sa.element_children.each do |item|
        p.add "<hr><b>#{sa.attr('name')}[#{i}]</b><br />\n"
        i += 1

        string = String.new
        c = item.child
        while c != nil do
          string += c.to_s
          c = c.next
        end

        #s2 = string.dup
        #string = s2.gsub(/(\s+)/, " ").strip

        cols = 80
        rows = string.length / cols + 1

        if @gecko then
          gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
        else
          gecko_hack = ""
        end

        p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>\n}
      end
    end

    p.title = "#{Time.now - @t} seconds"
    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def show_strings
    p = XhtmlPage.new

    doc = Nokogiri::XML(@en_strings_xml)

    doc.xpath('//string').each do |s|
      p.add "<hr><b>#{s.attr('name')}</b><br />\n"

      string = String.new
      c = s.child
      while c != nil do
        string += c.to_s
        c = c.next
      end

      s2 = string.dup
      string = s2.gsub(/(\s+)/, " ").strip

      cols = 80
      rows = string.length / cols + 1

      if @gecko then
        gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
      else
        gecko_hack = ""
      end

      p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>}
    end

    doc.xpath('//string-array').each do |sa|
      i = 0
      sa.element_children.each do |item|
        p.add "<hr><b>#{sa.attr('name')}[#{i}]</b><br />\n"
        i += 1

        string = String.new
        c = item.child
        while c != nil do
          string += c.to_s
          c = c.next
        end

        #s2 = string.dup
        #string = s2.gsub(/(\s+)/, " ").strip

        cols = 80
        rows = string.length / cols + 1

        if @gecko then
          gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
        else
          gecko_hack = ""
        end

        p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>\n}
      end
    end

    p.title = "#{Time.now - @t} seconds"
    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def show_cached_strings
    p = XhtmlPage.new

    @strings.each do |name, string|
      p.add "<hr><b>#{name}</b><br />\n"

      cols = 80
      rows = string.length / cols + 1

      if @gecko then
        gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
      else
        gecko_hack = ""
      end

      p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>}
    end

    @str_ars.each do |name, a|
      i = 0
      a.each do |string|
        p.add "<hr><b>#{name}[#{i}]</b><br />\n"
        i += 1

        cols = 80
        rows = string.length / cols + 1

        if @gecko then
          gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
        else
          gecko_hack = ""
        end

        p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>\n}
      end
    end

    #p.title = "#{Time.now - @t} seconds"
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
      string = s2.gsub(/(\s+)/, " ").strip

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

socket_name = '/tmp/ath.sock'

i = ARGV[0].to_i
socket_name += "-#{i}" if i > 0

#Rack::Handler::FastCGI.run(AndroidTranslationHelper.new(), :File => socket_name)
Rack::Handler::Thin.run(AndroidTranslationHelper.new())
