# encoding: utf-8

require 'cgi'
require './s3_storage.rb'
require './local_storage.rb'
require './mongo_storage.rb'
require './language.rb'
require './dsts-ext.rb'
require 'benchmark'

class AndroidTranslationHelper
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
    p = AthPage.new(@gecko_p)
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

    p = AthPage.new(@gecko_p)
    p.title = "Translate to #{Language::Languages.key(lang)}"
    p.add %Q{<p><a href="/ath/bi/">Home</a></p>}
    p.add "<h2>#{p.title}</h2>\n"

    @trans_ins ||= IO.read('translation_instructions.html')
    p.add @trans_ins

    p.add %Q{<form action="" method="post">\n}
    p.add %Q{<input type="hidden" name="_ath_translated_from" value="#{Time.now.to_f}" />\n}

    @strings['en'].each do |key, value|
      p.add_trans_str_section(key, {'en' => @strings['en'][key]['string'],
                                    lang => @strings[lang][key]['string']},
                              :quoted => @strings['en'][key]['quoted'])
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
      container = strings
      container = conflicts if @strings[lang][key] and
                               @strings[lang][key]['modified_at'] > translated_from and
                               value != @strings[lang][key]['string']

      container[key] = {'string' => value, 'quoted' => @strings['en'][key]['quoted']}
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
      p.add_trans_str_section(key, {            'en' => @strings['en'][key]['string'],
                                    "#{lang}-yours"  => @strings[lang][key]['string'],
                                    "#{lang}-theirs" => value['string']},
                              :quoted => @strings['en'][key]['quoted'], :no_anchor => true)
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
