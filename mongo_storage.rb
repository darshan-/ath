# encoding: utf-8

require 'mongo'
require './lib/nicer_nil.rb'

class MongoStorage
  def initialize()
    @db = Mongo::Connection.new.db("test_ath_bi")
    # TODO: exit cleanly (and clearly) if mongod not running...
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
      next if current[name]['string'] == hash['string']
      next if hash['string'].empty? and not current.has_key?(name)

      hash['modified_at'] = Time.now.to_f
      update.push('name' => name, 'hash' => hash)
      current[name] = hash
    end

    c.insert(update)

    current
  end
end
