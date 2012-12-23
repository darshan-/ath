# encoding: utf-8

require 'nokogiri'
require 'cgi'

require './str_helper.rb'

module XMLHelper
  extend self # So methods don't have to be defined with self.method_name

  def xml_to_str(xml)
    strings = {}

    parse_string = lambda do |element|
      return {'string' => nil} if element.nil?

      s = ''

      # element.text strips HTML like <b> and/or <i> that we want to keep, so we loop over the children
      #  taking each child's to_xml to preserve them.  Manually setting encoding seems to be necessary
      #  to preserve multi-byte characters.
      element.children.each do |c|
        s << c.to_xml(:encoding => 'utf-8')
      end

      s = StrHelper.clean(s).gsub(/\\("|')/, '\1')

      {'string' => s}
    end

    doc = Nokogiri::XML(xml)

    doc.xpath('//string').each do |str_el|
      strings[str_el.attr('name')] = parse_string.call(str_el)
    end

    doc.xpath('//string-array').each do |sa_el|
      sa_el.element_children.each_with_index do |item_el, i|
        strings[sa_el.attr('name') << "[#{i}]"] = parse_string.call(item_el)
      end
    end

    doc.xpath('//plurals').each do |sp_el|
      %w(zero one two few many other).each do |quantity|
        strings[sp_el.attr('name') << "[:#{quantity}]"] = parse_string.call(sp_el.element_children.at("[@quantity=#{quantity}]"))
      end
    end

    strings
  end

  def str_to_xml(strings, model_strings = nil)
    doc = Nokogiri::XML('')
    res = Nokogiri::XML::Node.new('resources', doc)
    doc.add_child(res)

    str_ars = {}
    str_pls = {}
    errors  = {}

    model_strings ||= strings

    model_strings.keys.each do |key|
      value = strings[key]

      if not key =~ /\[/   # string
        next if value.nil? or value['string'].empty?

        e = check_tags(value['string'])
        errors[key] = e if e
        next if not errors.empty?

        str = Nokogiri::XML::Node.new('string', doc)
        str['name'] = key
        str['formatted'] = 'false'
        str.content = str_hash_to_s(value)
        res.add_child(str)
      elsif not key =~ /:/ # string-array
        name = key.split('[').first

        # TODO: At first glance, this seems to mostly work, but I don't want to copy everything from model if array is empty, only the missing items of a partial array
        #   Might think about how to fix it here, or filter out downstream by removing arrays that are identical to en
        value ||= model_strings[key]

        e = check_tags(value['string'])
        errors[name] = e if e
        next if not errors.empty?

        str_ars[name] ||= Nokogiri::XML::Node.new('string-array', doc)
        str_ars[name]['name'] = name

        item = Nokogiri::XML::Node.new('item', doc)
        item.content = str_hash_to_s(value)
        str_ars[name].add_child(item)
      else                 # plural
        next if value.nil? or value['string'].empty?
        name = key.split('[').first
        quantity = key.split(':')[1].split(']').first

        e = check_tags(value['string'])
        errors[name] = e if e
        next if not errors.empty?

        str_pls[name] ||= Nokogiri::XML::Node.new('plurals', doc)
        str_pls[name]['name'] = name

        item = Nokogiri::XML::Node.new('item', doc)
        item['quantity'] = quantity
        item.content = str_hash_to_s(value)
        str_pls[name].add_child(item)
      end
    end

    if not errors.empty?
      s = ""

      errors.each do |name, error|
        s << "#{name}:\n\t#{error}\n"
      end

      return s
    end

    str_ars.values.each do |a|
      res.add_child(a)
    end

    str_pls.values.each do |p|
      res.add_child(p)
    end

    CGI.unescapeHTML(doc.to_xml(:encoding => 'utf-8'))
  end

  private

  def str_hash_to_s(hash)
    escape_quotes(hash['string']).gsub(/\r|\n/, '')
  end

  # I couldn't figure out how to make a regex do this for me...
  #  (the hard part being: not escaping quotes that are within a tag)
  def escape_quotes(s)
    i = 0
    len = s.length
    brackets = 0

    while i < len do
      if s[i] == '<' then brackets += 1 end
      if s[i] == '>' then brackets -= 1 end

      if brackets < 1 and (s[i] == "'" or s[i] == '"')
        unless (i == 0 or i == len - 1) and StrHelper::quoted?(s)
          s.insert(i, '\\')
          i += 1
          len += 1
        end
      end

      i += 1
    end

    s
  end

  def check_tags(s)
    open_tags = []
    cur_tag = nil
    cur_tag_extras = nil
    is_end_tag = false

    i = 0
    len = s.length
    while (i < len) do
      c = s[i]

      if c == '<'
        if cur_tag
          return "Unclosed open-bracket at index #{i}: <#{cur_tag}"
        else
          cur_tag = ""
          cur_tag_extras = nil
          is_end_tag = false
        end
      elsif c == '>'
        if cur_tag
          return "Empty tag at index #{i}" if cur_tag.length == 0

          if is_end_tag
            if cur_tag_extras and cur_tag_extras.length > 0
              return "End tag with attributes at index #{i}: <#{cur_tag} #{cur_tag_extras}>"
            elsif cur_tag == open_tags.last
              open_tags.pop
              cur_tag = nil
            else
              return "Close tag </#{cur_tag}> does not match open tag <#{open_tags.last}> at index #{i}"
            end
          else
            if s[i-1] != '/'
              open_tags.push(cur_tag)
            end

            if cur_tag_extras and not cur_tag_extras.match(/^(\s[a-z]+="[^"]*")+\/?$/)
              return "Bad attrubutes '#{cur_tag_extras}' in tag <#{cur_tag}> at index #{i}"
            end

            cur_tag = nil
          end
        else
          return "Close-bracket where it doesn't belong at index #{i}"
        end
      elsif c == ' ' and cur_tag == ''
        return "Space at begining of tag at index #{i}"
      elsif c == ' ' and cur_tag and is_end_tag
        return "Space in end tag '</#{cur_tag}' at index #{i}"
      elsif c == ' ' and cur_tag and not cur_tag_extras
        cur_tag_extras = " "
      elsif c == '/' and s[i-1] == '<'
        is_end_tag = true
      elsif cur_tag
        if not cur_tag_extras
          cur_tag << c
        else
          cur_tag_extras << c
        end
      end

      i += 1
    end

    return "Unclosed tag: <#{open_tags.pop}>" if not open_tags.empty?
    return "Unclosed open-bracket: <#{cur_tag}" if cur_tag

    nil
  end
end
