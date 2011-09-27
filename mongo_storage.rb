# encoding: utf-8

require 'mongo'

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

    c.distinct('name').each do |name|
      strings[name] = c.find_one({'name' => name}, {:sort => ['hash.updated', :desc]})['hash']
    end

    strings
  end

  def put_strings(lang, strings)
    c = @db.collection(lang)

    strings.each do |name, hash|
      next if c.find_one({'name' => name}, {:sort => ['hash.updated', :desc]})['hash']['string'] == hash['string']

      hash['updated'] = Time.now
      c.insert('name' => name, 'hash' => hash)
    end

    c.ensure_index([['name', Mongo::ASCENDING], ['hash.updated', Mongo::DESCENDING]])
  end
end
