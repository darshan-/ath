# encoding: utf-8

require 'mongo'

class MongoStorage
  def initialize()
    @db = Mongo::Connection.new.db("test_ath_bi")
    # TODO: exit cleanly (and clearly) if mongod not running...
  end

  def get_langs()
    @db.collection_names.delete_if {|i| i =~ /\./} - ['en'] # Mongo system collections all have a dot
  end

  def get_strings(lang)
  end

  def put_strings(lang, strings)
    # For each item, update the timestamp if and only if the item has changed
  end
end
