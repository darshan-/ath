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
    c = @db.collection(lang)

    strs = c.find_one()

    { :strings => strs['strings'],
      :str_ars => strs['str_ars'],
      :str_pls => strs['str_pls'] }
  end

  def put_strings(lang, strings)
    c = @db.collection(lang)

    c.insert(strings)
  end
end
