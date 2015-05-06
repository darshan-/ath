# encoding: utf-8

require 'mongo'
require './lib/nicer_nil.rb'

class MongoStorage
  DB_BASENAME = 'ath_'

  def initialize(app_code)
    @db = Mongo::Connection.new.db(DB_BASENAME + app_code)
    #@db = Mongo::Client.new([ '127.0.0.1:27017' ], :database => DB_BASENAME + app_code).database
  end

  def get_langs()
    @db.collection_names.to_a.delete_if {|i| i =~ /\./} - ['en'] # Mongo system collections all have a dot
  end

  def get_strings(lang)
    strings = {}
    c = @db.collection(lang)

    c.find.each_entry do |entry|
      if strings[entry['name']].nil? || strings[entry['name']]['modified_at'] < entry['hash']['modified_at']
        strings[entry['name']] = entry['hash']
      end
    end

    strings
  end

  def put_strings(lang, strings)
    c = @db.collection(lang)

    current = get_strings(lang)
    update = []

    strings.each do |name, hash|
      if lang == 'en'
        if current[name]['string'] == hash['string']
          hash['modified_at'] = current[name]['modified_at']
        end
      else
        next if current[name]['string'] == hash['string']
        next if hash['string'].empty? and not current.has_key?(name)
      end

      hash['modified_at'] ||= Time.now.to_f
      update.push('name' => name, 'hash' => hash)
      current[name] = hash
    end

    c.insert(update)

    if lang == 'en'
      old_size = c.stats()['size']
      @db.drop_collection(lang)
      @db.create_collection(lang, {:capped => true, :size => old_size * 1.1})
      c = @db.collection(lang)
      c.insert(update)
      current = get_strings(lang)
    end

    current
  end
end
