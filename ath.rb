# -*- coding: utf-8 -*-
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

    if @path.empty? then
      home()
    elsif @path[0] == "keepalive" then
      keepalive()
    #elsif @path[0] == "__FILE__" then
    #  [200, {"Content-Type" => "text/plain"}, File.new(__FILE__).read]
    elsif m == "POST" and @path[0] == "post_strings" then
      post_strings()
    elsif @path[0] == "upload_strings" then
      show_upload_form()
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

    add_string = lambda do |name, hash|
      p.add "<hr><b>#{name}</b><br />\n"

      cols = 80
      rows = hash[:rows]
      string = hash[:string]

      if @gecko then
        gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
      else
        gecko_hack = ""
      end

      p.add %Q{<textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{string}</textarea>}
    end

    @strings.each do |name, hash|
      add_string.call(name, hash)
    end

    @str_ars.each do |name, array|
      i = 0
      array.each do |hash|
        add_string.call(name + "[#{i}]", hash)
        i += 1
      end
    end

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def cache_strings
    @strings = {}
    @str_ars = {}

    parse_string = lambda do |element|
      h = {}
      s = ''

      # Doesn't account for word-wrapping, but gets plenty close for now
      count_rows = lambda do |s|
        col = 1
        row = 1

        s.each_char do |c|
          if c == "\n" then
            puts "NL(#{row})"
            col = 1
            row += 1
            next
          end
          print c

          if col > TA_COLS then
            puts "80(#{row})"
            col = 1
            row += 1
            next
          end

          col += 1
        end

        puts "(#{row})\n-----------------"
        row
      end

      # element.text strips HTML like <b> and/or <i> that we want to keep, so we loop over the children
      #  taking each child's to_xml to preserve them.
      c = element.child
      while c != nil do
        s += c.to_xml(:encoding => 'utf-8')
        c = c.next
      end
      
      if s[0] == '"' and s[s.length-1] == '"' then
        h[:quoted] = true
        s = s[1, s.length-2]
      end

      s = s.dup.gsub(/(\s+)/, ' ').gsub(/\\n\ \\n/, "\\n\\n").gsub(/\\n/, "\\n\n").strip

      h[:string] = s
      h[:rows] = count_rows.call(s)

      h
    end

    doc = Nokogiri::XML(@en_strings_xml)

    doc.xpath('//string').each do |str_el|
      h = parse_string.call(str_el)

      @strings[str_el.attr('name')] = h
    end

    doc.xpath('//string-array').each do |sa_el|
      @str_ars[sa_el.attr('name')] = Array.new()

      i = 0
      sa_el.element_children.each do |item_el|
        h = parse_string.call(item_el)

        @str_ars[sa_el.attr('name')][i] = h
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
