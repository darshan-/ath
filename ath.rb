# encoding: utf-8

require 'cgi'
require './s3_storage.rb'
require './local_storage.rb'
require './mongo_storage.rb'
require './language.rb'
require './dsts-ext.rb'
require 'benchmark'

class AndroidTranslationHelper
  TA_COLS = 80 # How many columns to use for the strings' textareas
  NOT_FOUND = [404, {'Content-Type' => 'text/plain'}, '404 - Not Found' + ' '*512] # Padded so Chrome shows the 404
  STORAGE_CLASS = MongoStorage

  def initialize()
    @storage = STORAGE_CLASS.new

    m = Benchmark.measure do
      initialize_cache()
    end

    puts "#{Time.now}: Loaded all strings in #{sprintf('%.3f', m.total)} seconds."
  end

  # Test with, e.g.: app.call({'HTTP_USER_AGENT' => '', 'REQUEST_URI' => '/ath/bi'})
  def call(env)
    @env = env
    @gecko_p = @env['HTTP_USER_AGENT'].match(/(?<!like )gecko/i)

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
    elsif @path[0] == 'reload_strings'
      reload_en()
    elsif @path[0] == 'translate_to'
      if m == 'POST'
        post_translate_form(@path[1], Rack::Request.new(@env).params)
      else
        show_translate_form(@path[1])
      end
    else
      NOT_FOUND
    end
  end

  def initialize_cache()
    @strings = {}

    (@storage.get_langs() + ['en']).each do |lang|
      @strings[lang] = @storage.get_strings(lang)
    end
  end

  def reload_strings()
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
    return true  if @strings.has_key?(lang)
    return false if lang.nil?
    return false if lang == 'en' # Not valid to edit en through web
    return false if not Language::Languages.has_value?(lang)

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
      return nil if s.nil?

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
      
      en_string = en_hash['string']
      xx_string = xx_hash['string']
      en_rows = count_rows.call(en_string) || 1
      xx_rows = count_rows.call(xx_string) || en_rows

      en_gecko_hack = xx_gecko_hack = ""
      if @gecko_p then
        en_gecko_hack = %Q{style="height:#{en_rows * 1.3}em;"}
        xx_gecko_hack = %Q{style="height:#{xx_rows * 1.3}em;"}
      end

      p.add %Q{en:<br />\n<textarea }
      p.add %Q{cols="#{cols}" rows="#{en_rows}" #{en_gecko_hack}>#{en_string}</textarea><br />\n}
      p.add %Q{#{lang}:<br />\n<textarea name="#{name}" }
      p.add %Q{cols="#{cols}" rows="#{xx_rows}" #{xx_gecko_hack}>#{xx_string}</textarea>\n}

      if en_hash['quoted'] then
        p.add %Q{<br />*<i>Spaces at the beginning and/or end of this one are important.</i> }
        p.add %Q{<b>Be sure to match the original</b> (unless you really should do something different in your language).}
      end
    end

    p.add %Q{<form action="" method="post">}

    @strings['en'].each do |name, content|
      hint = content.first[1]

      if hint.is_a? String  # string
        add_string.call(name, content, @strings[lang][name])
      elsif hint.is_a? Hash # plural
        %w(zero one two few many other).each do |quantity|
          add_string.call(name + "[#{quantity}]", content[quantity], @strings[lang][name][quantity])
        end
      else                  # string-array
        i = 0
        content.each do |str_hash|
          add_string.call(name + "[#{i}]", str_hash, @strings[lang][name][i])
          i += 1
        end
      end
    end

    p.add "</form>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
  end

  def post_translate_form(lang, params)
    return NOT_FOUND unless valid_lang?(lang)

    anchor = nil
    params.each_key do |key|
      if key.match(/^_ath_submit_(.*)/)
        anchor = $1;
        params.delete(key)
        break
      end
    end

    all_empty = lambda do |hash|
      hash.each_value {|v| return false unless v.empty?}
      return true
    end

    strings = {}

    params.each do |key, value|
      next if value.empty?

      if value.is_a? Hash
        next if all_empty.call(value)

        if value.has_key? '0'
          strings[key] = []

          value.each do |k, v|
            i = k.to_i
            strings[key][i] = {'string' => v, 'quoted' => @strings['en'][key][i]['quoted']}
          end
        else
          strings[key] = {}

          value.each do |q, v|
            next if v.empty?

            strings[key][q] = {'string' => v, 'quoted' => @strings['en'][key][q]['quoted']}
          end
        end
      else
        strings[key] = {'string' => value, 'quoted' => @strings['en'][key]['quoted']}
      end
    end

    @strings[lang] = strings

    @storage.put_strings(lang, @strings[lang])

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
end
