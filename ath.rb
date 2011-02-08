# -*- coding: utf-8 -*-
require 'nokogiri'
require 'cgi'
require './s3storage.rb'
require './language.rb'
require './dsts-ext.rb'

class AndroidTranslationHelper
  TA_COLS = 80 # How many columns to use for the strings' textareas
  NOT_FOUND = [404, {'Content-Type' => 'text/plain'}, '404 - Not Found' + ' '*512] # Padded so Chrome shows the 404

  def initialize()
    @storage = S3Storage.new()
    initialize_cache()
  end

  # Test with, e.g.: app.call({'HTTP_USER_AGENT' => '', 'REQUEST_URI' => '/ath/bi'})
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

    return NOT_FOUND unless @path[0] == 'bi'
    @path.delete_at(0)

    if @path.empty? then
      home()
    elsif @path[0] == 'clear_cache'
      clear_cache()
    elsif @path[0] == 'translate_to'
      if m == 'POST'
        post_translate_form(@path[1])
      else
        show_translate_form(@path[1])
      end
    else
      default()
    end
  end

  def initialize_cache()
    @strings = {}
    @str_ars = {}
    cache_strings('en')
  end

  def clear_cache()
    initialize_cache()
    [302, {'Location' => '/ath/bi/'}, '302 Found']
  end

  def default()
    p = AthPage.new
    path = @path.join(', ')

    p.title = "#{path}"
    p.add "<p><b>Path:</b> #{path}</p>"
    p.add "<div>" << dump_env() << "</div>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
  end

  def home()
    p = AthPage.new
    p.title = "Battery Indicator Translation Helper"

    p.add "<h2>#{p.title}</h2>\n"

    p.add "<b>Work on an existing translation:</b>\n"
    p.add "<ul>"
    @storage.get_langs.each do |lang|
      p.add %Q{<li><a href="/ath/bi/translate_to/#{lang}">#{Language::Languages[lang]}</a></li>\n}
    end
    p.add "</ul>"

    p.add "<b>Start a new translation:</b>\n"
    p.add "<ul>"
    (Language::Languages.keys - @storage.get_langs - ['en']).each do |lang|
      p.add %Q{<li><a href="/ath/bi/translate_to/#{lang}">#{Language::Languages[lang]}</a></li>\n}
    end
    p.add "</ul>"

    p.add "<b>If the language you'd like to translate to isn't listed, "
    p.add "please email me via the contact info listed in the Android Market.</b>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
  end

  def valid_lang?(lang)
    return false if lang.nil?

    if @strings[lang].nil?
      cache_strings(lang)
      return false if @strings[lang].nil?
    end

    return false if lang == 'en'

    true
  end

  def show_translate_form(lang)
    return NOT_FOUND unless valid_lang?(lang)

    p = AthPage.new()
    p.title = "Translate to #{Language::Languages[lang]}"
    p.add "<h2>#{p.title}</h2>\n"

    @trans_ins || File.open('translation_instructions.html') {|f| @trans_ins = f.read()}
    p.add @trans_ins

    add_string = lambda do |name, en_hash, xx_hash|
      anchor_name = name.gsub(/\[|\]/, '')
      p.add %Q{<hr><div><a name="#{anchor_name}"><b>#{name}#{'*' if en_hash[:quoted]}</b></a>}
      p.add %Q{<input style="float: right;" type="submit" name="_ath_submit_#{anchor_name}" value="Save All" /></div>\n}

      cols = TA_COLS
      en_rows = en_hash[:rows]
      xx_rows = xx_hash[:rows] || en_rows
      en_string = en_hash[:string]
      xx_string = xx_hash[:string]

      en_gecko_hack = xx_gecko_hack = ""
      if @gecko then
        en_gecko_hack = %Q{style="height:#{en_rows * 1.3}em;"}
        xx_gecko_hack = %Q{style="height:#{xx_rows * 1.3}em;"}
      end

      p.add %Q{en:<br />\n<textarea }
      p.add %Q{cols="#{cols}" rows="#{en_rows}" #{en_gecko_hack}>#{en_string}</textarea><br />\n}
      p.add %Q{#{lang}:<br />\n<textarea name="#{name}" }
      p.add %Q{cols="#{cols}" rows="#{xx_rows}" #{xx_gecko_hack}>#{xx_string}</textarea>\n}

      if en_hash[:quoted] then
        p.add %Q{<br />*<i>Spaces at the beginning and/or end of this one are important.</i> }
        p.add %Q{<b>Be sure to match the original</b> (unless you really should do something different in your language).}
      end
    end

    p.add %Q{<form action="" method="post">}

    @strings['en'].each do |name, hash|
      add_string.call(name, hash, @strings[lang][name])
    end

    @str_ars['en'].each do |name, array|
      i = 0
      array.each do |hash|
        add_string.call(name + "[#{i}]", hash, @str_ars[lang][name][i])
        i += 1
      end
    end

    p.add "</form>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
  end

  def post_translate_form(lang)
    return NOT_FOUND unless valid_lang?(lang)

    params = Rack::Request.new(@env).params
    doc = Nokogiri::XML('')
    res = Nokogiri::XML::Node.new('resources', doc)
    doc.add_child(res)

    anchor = nil
    params.each_key do |key|
      if key.match(/^_ath_submit_(.*)/)
        anchor = $1;
        params.delete(key)
      end
    end

    all_empty = lambda do |hash|
      hash.each_value {|v| return false unless v.empty?}
      return true
    end

    # I couldn't figure out how to make a regex do this for me...
    #  (the hard part being: not escaping quotes that are within a tag)
    escape_quotes = lambda do |s|
      i = 0
      len = s.length
      brackets = 0

      while i < len do
        if s[i] == '<' then brackets += 1 end
        if s[i] == '>' then brackets -= 1 end

        if brackets < 1 && (s[i] == "'" || s[i] == '"')
          s.insert(i, "\\")
          i += 1
          len += 1
        end

        i += 1
      end

      s
    end

    quote_or_clean = lambda do |s, quote|
      return %Q{"#{s}"} if quote

      s.gsub(/\r|\n/, '').gsub(/\s+/, ' ').strip
    end

    params.each do |key, value|
      next if value.empty?

      if value.is_a? Hash
        next if all_empty.call(value)

        str_ar = Nokogiri::XML::Node.new('string-array', doc)
        str_ar['name'] = key

        value.each do |i, v|
          item = Nokogiri::XML::Node.new('item', doc)
          item.content = quote_or_clean.call( escape_quotes.call(v),
                                              @strings['en'][key][i][:quoted])
          str_ar.add_child(item)
        end

        res.add_child(str_ar)
      else
        str = Nokogiri::XML::Node.new('string', doc)
        str['name'] = key
        str.content = quote_or_clean.call( escape_quotes.call(value),
                                           @strings['en'][key][:quoted])
        res.add_child(str)
      end
    end

    #return [200, {'Content-Type' => 'text/plain'}, CGI.unescapeHTML(doc.to_xml(:encoding => 'utf-8'))]

    @storage.put_strings(lang, CGI.unescapeHTML(doc.to_xml(:encoding => 'utf-8')))
    cache_strings(lang)

    [302, {'Location' => @env['REQUEST_URI'] + '#' << anchor}, '302 Found']
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
      @strings[lang][str_el.attr('name')] = parse_string.call(str_el)
    end

    doc.xpath('//string-array').each do |sa_el|
      @str_ars[lang][sa_el.attr('name')] = []

      sa_el.element_children.each_with_index do |item_el, i|
        @str_ars[lang][sa_el.attr('name')][i] = parse_string.call(item_el)
      end
    end
  end

  def dump_env
    s = ''

    s << "<hr />\n<p><i>" << Time.new.to_s << "</i></p>\n"
    s << "<br />\nEnvironment:<br />\n"
    @env.each do |key, value|
      s << "* #{key} =&gt; #{CGI.escapeHTML(value.to_s)}<br />\n"
    end

    s
  end
end
