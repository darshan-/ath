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
    #strings = {}
    #str_ars = {}
    #str_pls = {}

    c = @db.collection(lang)

    #c.find.each do |item|
    #  if item.has_key?('string')
    #    strings[item['name']] = item['string']
    #  elsif item.has_key?('str_ar')
    #    str_ars[item['name']] = item['str_ar']
    #  elsif item.has_key?('str_pl')
    #    str_pls[item['name']] = item['str_pl']
    #  end
    #end

    strs = c.find_one()

    { :strings => strs['strings'],
      :str_ars => strs['str_ars'],
      :str_pls => strs['str_pls'] }
  end

  def put_strings(lang, strings)
    c = @db.collection(lang)

    c.insert(strings)

    #strings[:strings].each do |k, v|
    #  c.insert({:name => k, :string => v.values.first})
    #end

    #strings[:str_ars].each do |k, v|
    #  c.insert({:name => k, :str_ar => v})
    #end

    #strings[:str_pls].each do |k, v|
    #  c.insert({:name => k, :str_pl => v})
    #end
  end
end
