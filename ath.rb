# encoding: utf-8

require 'benchmark'
require 'cgi'

require './dsts-ext.rb'
require './language.rb'
require './mongo_storage.rb'
require './str_helper.rb'
require './xml_helper.rb'

class AndroidTranslationHelper
  NOT_FOUND = [404, {'Content-Type' => 'text/plain'}, '404 - Not Found' + ' '*512] # Padded so Chrome shows the 404
  STORAGE_CLASS = MongoStorage
  INCOMING_EN = 'incoming/en.xml'

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

    # REQUEST_URI starts with a slash, so delete blank first element
    @path.delete_at(0)

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

    if @path.empty? and m == 'GET' then
      home()
    elsif @path[0] == 'translate_to' and @path.length == 2
      if m == 'POST'
        post_translate_form(@path[1], Rack::Request.new(@env).params)
      else
        show_translate_form(@path[1])
      end
    elsif @path[0] == 'langs' and m == 'GET' and @path.length <= 2
      if @path.length == 1
        langs()
      else
        lang_xml(@path[1])
      end
    elsif @path[0] == 'load_new_en' and m == 'POST' and @path.length == 1
      load_new_en()
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

  def home()
    p = AthPage.new(@gecko_p)
    existing = @storage.get_langs()
    unstarted = Language::Languages.values - existing - ['en']

    list_links = lambda do |codes|
      p.add "<ul>"
      Language::Languages.each do |lang, code|
        next if !codes.include?(code)
        p.add %Q{<li><a href="/bi/translate_to/#{code}">#{lang}</a></li>\n}
      end
      p.add "</ul>"
    end

    p.title = "Battery Indicator Translation Helper"
    p.add "<h2>#{p.title}</h2>\n"

    p.add "<b>Work on an existing translation:</b>\n"
    list_links.call(existing)

    p.add "<b>Start a new translation:</b>\n"
    list_links.call(unstarted)

    p.add "<b>If the language you'd like to translate to isn't listed, please email me.</b>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
  end

  def langs()
    [200, {'Content-Type' => 'text/plain'}, @storage.get_langs().join(' ')]
  end

  def lang_xml(lang)
    return NOT_FOUND unless valid_lang?(lang)

    [200, {'Content-Type' => 'text/plain'}, XMLHelper.str_to_xml(@storage.get_strings(lang))]
  end

  # After `scp'ing the file in, use one of these:
  # wget --quiet -O /dev/null --ignore-length --post-data="" http://<host>/bi/load_new_en
  # curl --silent --fail --data "" http://<host>/bi/load_new_en
  def load_new_en()
    return NOT_FOUND unless File.exists?(INCOMING_EN)

    @storage.put_strings('en', XMLHelper.xml_to_str(IO.read(INCOMING_EN)))
    @strings['en'] = @storage.get_strings('en') # Store and then retrieve to get mtimes

    File.delete(INCOMING_EN)

    [204, {}, '']
  end

  def valid_lang?(lang)
    return false if lang == 'en'            # Not valid to edit en through web

    return true  if @strings.has_key?(lang) # Valid existing translation

    return false if lang.nil?
    return false if not Language::Languages.has_value?(lang)

    true                                    # Valid lang for a new translation
  end

  def show_translate_form(lang)
    return NOT_FOUND unless valid_lang?(lang)

    p = AthPage.new(@gecko_p)
    p.title = "Translate to #{Language::Languages.key(lang)}"
    p.add %Q{<p><a href="/bi/">Home</a></p>}
    p.add "<h2>#{p.title}</h2>\n"

    @trans_ins ||= IO.read('translation_instructions.html')
    p.add @trans_ins

    p.add %Q{<form action="" method="post">\n}
    p.add %Q{<input type="hidden" name="_ath_translated_from" value="#{Time.now.to_f}" />\n}

    plurals = {}

    @strings['en'].each do |key, value|
      if key =~ /\[:/ # plural
        plurals[key.split('[').first] = nil
        next
      end

      p.add_trans_str_section(key, {'en' => @strings['en'][key]['string'],
                                    lang => @strings[lang][key]['string']})
    end

    plurals.keys.each do |key_base|
      %w(zero one two few many other).each do |quantity|
        key = "#{key_base}[:#{quantity}]"
        p.add_trans_str_section(key, {'en' => @strings['en'][key]['string'],
                                      lang => @strings[lang][key]['string']})
      end
    end

    p.add "</form>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
  end

  def post_translate_form(lang, params)
    return NOT_FOUND unless valid_lang?(lang)

    anchor = ''
    params.each_key do |key|
      if key.match(/^_ath_submit_(.*)/)
        anchor = $1
        params.delete(key)
        break
      end
    end

    translated_from = params['_ath_translated_from'].to_f
    params.delete('_ath_translated_from')

    strings = {}
    conflicts = {}

    insert_value = lambda do |value, key|
      value = StrHelper::clean(value)

      container = strings
      container = conflicts if @strings[lang][key] and
                               @strings[lang][key]['modified_at'] > translated_from and
                               value != @strings[lang][key]['string']

      container[key] = {'string' => value}
    end

    params.each do |key, value|
      if value.is_a? Hash
        if value.has_key? '0' # string-array
          value.each do |k, v|
            insert_value.call(v, key + "[#{k.to_i}]")
          end
        else                  # plural
          value.each do |q, v|
            realkey = key + "[#{q}]"
            insert_value.call(v, realkey)
          end
        end
      else                    # string
        insert_value.call(value, key)
      end
    end

    @strings[lang] = @storage.put_strings(lang, strings)

    if conflicts.empty?
      [302, {'Location' => @env['REQUEST_URI'] + '#' << anchor}, '302 Found']
    else
      resolve_conflicts(lang, conflicts, anchor)
    end
  end

  def resolve_conflicts(lang, conflicts, anchor)
    p = AthPage.new(@gecko_p)
    p.title = "Conflicts Encountered!"
    p.add "<h2>#{p.title}</h2>\n"

    @conf_res_ins ||= IO.read('conflict_resolution_instructions.html')
    p.add @conf_res_ins

    p.add %Q{<form action="" method="post">\n}
    p.add %Q{<input type="hidden" name="_ath_translated_from" value="#{Time.now.to_f}" />\n}
    p.add %Q{<input type="hidden" name="_ath_submit_#{anchor}" value="1" />\n}

    conflicts.each do |key, value|
      p.add_trans_str_section(key, {'en'             => @strings['en'][key]['string'],
                                    "#{lang}-yours"  => @strings[lang][key]['string'],
                                    "#{lang}-theirs" => value['string']},
                              :no_anchor => true)
    end

    p.add "</form>"

    [200, {'Content-Type' => 'text/html'}, p.generate]
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
