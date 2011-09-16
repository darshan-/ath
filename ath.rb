# -*- coding: utf-8 -*-
require 'cgi'
require './s3_storage.rb'
require './local_storage.rb'
require './language.rb'
require './dsts-ext.rb'

# TODO:
#   Run cached strings in separate process?

class AndroidTranslationHelper
  TA_COLS = 80 # How many columns to use for the strings' textareas
  NOT_FOUND = [404, {'Content-Type' => 'text/plain'}, '404 - Not Found' + ' '*512] # Padded so Chrome shows the 404
  LOCAL = true

  def initialize()
    if LOCAL
      @storage = LocalStorage.new()
    else
      @storage = S3Storage.new()
    end

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

  private

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
      NOT_FOUND
    end
  end

  def initialize_cache()
    @strings = {}
    @str_ars = {}
    @str_pls = {}
    (@storage.get_langs() + ['en']).each do |lang|
      cache_strings(lang)
    end
  end

  def clear_cache()
    initialize_cache()
    [302, {'Location' => '/ath/bi/'}, '302 Found']
  end

  def home()
    p = AthPage.new
    existing = @storage.get_langs()
    unstarted = Language::Languages.values - existing - ['en']

    list_links = lambda do |codes|
      p.add "<ul>"
      Language::Languages.each do |lang, code|
        next if !codes.include?(code)
        p.add %Q{<li><a href="/ath/bi/translate_to/#{code}">#{lang}</a></li>\n}
      end
      p.add "</ul>"
    end

    p.title = "Battery Indicator Translation Helper"
    p.add "<h2>#{p.title}</h2>\n"

    p.add "<b>Work on an existing translation:</b>\n"
    list_links.call(existing)

    p.add "<b>Start a new translation:</b>\n"
    list_links.call(unstarted)

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
    p.title = "Translate to #{Language::Languages.key(lang)}"
    p.add %Q{<p><a href="/ath/bi/">Home</a></p>}
    p.add "<h2>#{p.title}</h2>\n"

    @trans_ins || File.open('translation_instructions.html') {|f| @trans_ins = f.read()}
    p.add @trans_ins

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

    add_string = lambda do |name, en_hash, xx_hash|
      anchor_name = name.gsub(/\[|\]/, '')
      p.add %Q{<hr><div><a name="#{anchor_name}"><b>#{name}#{'*' if en_hash[:quoted]}</b></a>}
      p.add %Q{<input style="float: right;" type="submit" name="_ath_submit_#{anchor_name}" value="Save All" /></div>\n}

      cols = TA_COLS
      
      en_string = en_hash[:string]
      xx_string = xx_hash[:string]
      en_rows = count_rows.call(en_string) || 1
      xx_rows = count_rows.call(xx_string) || en_rows

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

    @str_pls['en'].each do |name, plural|
      %w(zero one two few many other).each do |quantity|
        add_string.call(name + "[#{quantity}]", plural[quantity], @str_pls[lang][name][quantity])
      end
    end

    p.add "</form>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
  end

  def post_translate_form(lang)
    return NOT_FOUND unless valid_lang?(lang)

    params = Rack::Request.new(@env).params

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

    strings = {}
    str_ars = {}
    str_pls = {}

    params.each do |key, value|
      next if value.empty?

      if value.is_a? Hash
        next if all_empty.call(value)

        if value.has_key? '0'
          str_ars[key] = []

          value.each do |i, v|
            str_ars[key][i] = quote_or_clean.call(escape_quotes.call(validate_tags(v)),
                                                  @strings['en'][key][i][:quoted])
          end
        else
          str_pls[key] = {}

          value.each do |q, v|
            next if v.empty?

            str_pls[key][q] = quote_or_clean.call(escape_quotes.call(validate_tags(v)),
                                                  @strings['en'][key][q][:quoted])
          end
        end
      else
        strings[key] = quote_or_clean.call(escape_quotes.call(validate_tags(value)),
                                           @strings['en'][key][:quoted])
      end
    end

    @storage.put_strings(lang, {:strings => strings, :str_ars => str_ars, :str_pls => str_pls})

    [302, {'Location' => @env['REQUEST_URI'] + '#' << anchor}, '302 Found']
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

  # Makes sure tags are all clean and properly matched; necessary to avoid corrupting XML file
  def validate_tags(s)
    s = s.gsub(/(<)\s*/, '\1').gsub(/(<\/)\s*/, '\1').gsub(/\s*(>)/, '\1')

    open_tags = []
    cur_tag = nil
    cur_tag_extras = nil
    is_end_tag = false
    failure = false

    validate_attrs = lambda do |s|
      return if s.nil?
      s = s.gsub(/\s+/, ' ').gsub(/\s*=\s*/, '=').strip
      failure = !s.match(/^([a-z]+="[^"]*"\s*)*\/?$/)
    end

    i = 0
    while (i < s.length) do
      c = s[i]

      if c == '<'
        if cur_tag
          s.slice!(i)

          next
        else
          cur_tag = String.new
          cur_tag_extras = nil
          is_end_tag = false
        end
      elsif c == '>'
        if cur_tag
          if cur_tag.length > 0
            if is_end_tag
              if cur_tag_extras and cur_tag_extras.strip.length > 0
                failure = true
                break
              elsif cur_tag == open_tags.last
                open_tags.pop
                cur_tag = nil
              else
                failure = true
                break
              end
            else
              if s[i-1] != '/'
                open_tags.push(cur_tag)
              end

              validate_attrs.call(cur_tag_extras)
              break if failure

              cur_tag = nil
            end
          else
            if is_end_tag
              s.slice!(i-2..i)
              i -= 2
            else
              s.slice!(i-1..i)
              i -= 1
            end

            cur_tag = nil
            next
          end
        else
          s.slice!(i)

          next
        end
      elsif c == ' ' and cur_tag and not cur_tag_extras
        cur_tag_extras = String.new
      elsif c == '/' and s[i-1] == '<'
        is_end_tag = true
      elsif cur_tag
        if not cur_tag_extras
          cur_tag << c
        else
          cur_tag_extras << c
        end
      end

      i += 1
    end

    failure = true if not open_tags.empty?
    failure = true if cur_tag

    if failure
      s = s.gsub(/<|>/, '')
    end

    s
  end
end
