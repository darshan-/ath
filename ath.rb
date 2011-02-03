# -*- coding: utf-8 -*-
require 'nokogiri'
require 'cgi'
require './s3storage.rb'
require './language.rb'
require './dsts.rb'

TA_COLS = 80 # How many columns to use for the strings' textareas

class AndroidTranslationHelper
  def initialize()
    @storage = S3Storage.new()
    @strings = {}
    @str_ars = {}
    cache_strings('en')
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
    elsif @path[0] == 'show_cached_strings' then
      show_cached_strings()
    elsif @path[0] == 'translate_to'
      show_translate_form(@path[1])
    else
      default()
    end
  end

  def default()
    p = XhtmlPage.new
    path = @path.join(', ')

    p.title = "#{path}"
    p.add "<p><b>Path:</b> #{path}</p>"
    p.add "<div>" << dump_env() << "</div>"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def home()
    p = XhtmlPage.new
    p.title = "Android Translation Helper"

    p.add "<h2>#{p.title}</h2>\n"

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def show_translate_form(other_lang)
    if other_lang.nil? then
      return [404, {'Content-Type' => 'text/plain'}, '404 - Not Found']
    end

    if @strings[other_lang].nil? then
      cache_strings(other_lang)
      return [404, {'Content-Type' => 'text/plain'}, '404 - Not Found'] if @strings[other_lang].nil?
    end

    p = XhtmlPage.new
    p.title = 'translating'

    add_string = lambda do |name, en_hash, other_hash|
      p.add "<hr><b>#{name}#{'*' if en_hash[:quoted]}</b><br />\n"

      cols = TA_COLS
      rows = en_hash[:rows]
      en_string = en_hash[:string]
      other_string = other_hash[:string]

      if @gecko then
        gecko_hack = %Q{style="height:#{rows * 1.3}em;"}
      else
        gecko_hack = ""
      end

      p.add %Q{en:<br /><textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{en_string}</textarea><br />}
      p.add %Q{#{other_lang}:<br /><textarea cols="#{cols}" rows="#{rows}" #{gecko_hack}>#{other_string}</textarea>}

      if en_hash[:quoted] then
        p.add %Q{<br />*<i>Spaces at the beginning and/or end of this one are important.</i> <b>Be sure to match the original!</b>}
      end
    end

    @strings['en'].each do |name, hash|
      add_string.call(name, hash, @strings[other_lang][name])
    end

    @str_ars['en'].each do |name, array|
      i = 0
      array.each do |hash|
        add_string.call(name + "[#{i}]", hash, @str_ars[other_lang][name][i])
        i += 1
      end
    end

    [200, {"Content-Type" => "text/html"}, p.generate]
  end

  def cache_strings(lang)
    return if not Language::Languages.has_key?(lang)

    strings_xml = @storage.get_strings(lang)

    @strings[lang] = {}
    @str_ars[lang] = {}

    parse_string = lambda do |element|
      h = {}
      s = ''

      # Doesn't account for words that don't fit at the end starting new lines, but gets plenty close for now
      count_rows = lambda do |s|
        col = 1
        row = 1

        s.each_char do |c|
          if c == "\n" or col > TA_COLS then
            col = 1
            row += 1
            next
          end

          col += 1
        end

        row
      end

      # element.text strips HTML like <b> and/or <i> that we want to keep, so we loop over the children
      #  taking each child's to_xml to preserve them.  Manually setting encoding seems to be necessary
      #  to preserve multi-byte characters.
      element.children.each do |c|
        s << c.to_xml(:encoding => 'utf-8')
      end

      # gsub! returns nil if there is no match, so it's no good for chaining unless you know you always match
      s = s.gsub(/\s*\\n\s*/, '\n').gsub(/\s+/, ' ').gsub(/\\n/, "\\n\n").gsub(/\\("|')/, '\1').strip

      if s[0] == '"' and s[s.length-1] == '"' then
        h[:quoted] = true
        s = s[1, s.length-2]
      end

      h[:string] = s
      h[:rows] = count_rows.call(s)

      h
    end

    doc = Nokogiri::XML(strings_xml)

    doc.xpath('//string').each do |str_el|
      h = parse_string.call(str_el)

      @strings[lang][str_el.attr('name')] = h
    end

    doc.xpath('//string-array').each do |sa_el|
      @str_ars[lang][sa_el.attr('name')] = Array.new()

      i = 0
      sa_el.element_children.each do |item_el|
        h = parse_string.call(item_el)

        @str_ars[lang][sa_el.attr('name')][i] = h
        i += 1
      end
    end
  end

  def dump_env
    s = String.new

    s << "<hr />\n<p><i>" << Time.new.to_s << "</i></p>\n"
    s << "<br />\nEnvironment:<br />\n"
    @env.each do |key, value|
      s << "* #{key} =&gt; #{CGI.escapeHTML(value.to_s)}<br />\n"
    end

    s
  end
end
