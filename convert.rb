#!/usr/bin/env ruby
# encoding: utf-8

require 'nokogiri'
require 'mongo'

# ath down
# backup db

# read in convert.xml to see which how to convert the string-arrays
# for each lang in db
#   find the string-arrays that match the ones in convert.xml and for each
#     add new string with name from conversions and value from old array
#     drop array string

# ath up
# verify

def parse_string(element)
  return nil if element.nil?

  s = ''

  # element.text strips HTML like <b> and/or <i> that we want to keep, so we loop over the children
  #  taking each child's to_xml to preserve them.  Manually setting encoding seems to be necessary
  #  to preserve multi-byte characters.
  element.children.each do |c|
    s << c.to_xml(:encoding => 'utf-8')
  end

  s
end

conversions = {}

conv_doc = Nokogiri::XML(IO.read('./conversions.xml'))

conv_doc.xpath('//string-array').each do |sa_el|
  a = []

  sa_el.element_children.each_with_index do |item_el, i|
    a[i] = parse_string(item_el)
  end

  conversions[sa_el.attr('name')] = a
end

db = Mongo::Connection.new.db('ath_bi')
langs = db.collection_names.to_a.delete_if {|i| i =~ /\./} - ['en']

langs.each do |lang|
  existing = {}
  ars = {}

  c = db.collection(lang)

  c.find.each_entry do |entry|
    if ars[entry['name']].nil? || ars[entry['name']]['modified_at'] < entry['hash']['modified_at']
      if entry['name'] =~ /\[/ and not entry['name'] =~ /:/
        ars[entry['name']] = entry['hash']
      end
    end
  end

  ars.each do |old_name, a|
    update = []

    a_name = old_name.split("[")[0]
    i      = old_name.split("[")[1].split("]")[0].to_i
    value = a['string']
    new_name = conversions[a_name][i]

    puts "#{old_name}: #{a}"
    puts "  Would be renamed to: #{new_name}"

    if existing.has_key?(new_name)
      puts "Name #{new_name} already exists with content: #{existing[new_name]}"
      if existing[new_name] == value
        puts "  (Skipped) new content is the same: #{value}"
      else
        puts "  (Skipped) new content is different: #{value}"
      end
    else
      existing[new_name] = value
      # set up update
    end

    #c.insert(update)
  end
end
