# encoding: utf-8
require 'nokogiri'
require 'cgi'

module XMLHelper
  def self.xml_to_str(xml)
    strings = {}

    parse_string = lambda do |element|
      h = {}
      s = ''

      # element.text strips HTML like <b> and/or <i> that we want to keep, so we loop over the children
      #  taking each child's to_xml to preserve them.  Manually setting encoding seems to be necessary
      #  to preserve multi-byte characters.
      element.children.each do |c|
        s << c.to_xml(:encoding => 'utf-8')
      end

      # gsub! returns nil if there is no match, so it's no good for chaining unless you know you always match
      s = s.gsub(/\s*\\n\s*/, '\n').gsub(/\s+/, ' ').gsub(/\\n/, "\\n\n").gsub(/\\("|')/, '\1').strip

      if s[0] == '"' and s[s.length-1] == '"' then
        h['quoted'] = true
        s = s[1, s.length-2]
      end

      h['string'] = s

      h
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
      sp_el.element_children.each do |item_el|
        strings[sp_el.attr('name') << "[:#{item_el.attr('quantity')}]"] = parse_string.call(item_el)
      end
    end

    strings
  end

  def self.str_to_xml(strings)
    doc = Nokogiri::XML('')
    res = Nokogiri::XML::Node.new('resources', doc)
    doc.add_child(res)

    # I couldn't figure out how to make a regex do this for me...
    #  (the hard part being: not escaping quotes that are within a tag)
    escape_quotes = lambda do |s|
      i = 0
      len = s.length
      brackets = 0

      while i < len do
        if s[i] == '<' then brackets += 1 end
        if s[i] == '>' then brackets -= 1 end

        if brackets < 1 && (s[i] == "'" || s[i] == '"')
          s.insert(i, "\\")
          i += 1
          len += 1
        end

        i += 1
      end

      s
    end

    quote_or_clean = lambda do |s, quote_p|
      return %Q{"#{s}"} if quote_p

      s.gsub(/\r|\n/, '').gsub(/\s+/, ' ').strip
    end

    str_ars = {}
    str_pls = {}

    strings.each do |key, value|
      if not key =~ /\[/   # string
        next if value['string'].empty?
        str = Nokogiri::XML::Node.new('string', doc)
        str['name'] = key
        str['formatted'] = 'false'
        str.content = quote_or_clean.call(escape_quotes.call(validate_tags(value['string'])),
                                          value['quoted'])
        res.add_child(str)
      elsif not key =~ /:/ # string-array
        name = key.split('[').first

        str_ars[name] ||= Nokogiri::XML::Node.new('string-array', doc)
        str_ars[name]['name'] = name

        item = Nokogiri::XML::Node.new('item', doc)
        item.content = quote_or_clean.call(escape_quotes.call(validate_tags(value['string'])),
                                           value['quoted'])
        str_ars[name].add_child(item)
      else                 # plural
        next if value['string'].empty?
        name = key.split('[').first
        quantity = key.split(':')[1].split(']').first

        str_pls[name] ||= Nokogiri::XML::Node.new('plurals', doc)
        str_pls[name]['name'] = name

        item = Nokogiri::XML::Node.new('item', doc)
        item['quantity'] = quantity
        item.content = quote_or_clean.call(escape_quotes.call(validate_tags(value['string'])),
                                           value['quoted'])
        str_pls[name].add_child(item)
      end
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

  # Makes sure tags are all clean and properly matched; necessary to avoid corrupting XML file
  def self.validate_tags(s)
    s = s.gsub(/(<)\s*/, '\1').gsub(/(<\/)\s*/, '\1').gsub(/\s*(>)/, '\1')

    open_tags = []
    cur_tag = nil
    cur_tag_extras = nil
    is_end_tag = false
    failure = false

    validate_attrs = lambda do |s|
      return if s.nil?
      s = s.gsub(/\s+/, ' ').gsub(/\s*=\s*/, '=').strip
      failure = !s.match(/^([a-z]+="[^"]*"\s*)*\/?$/)
    end

    i = 0
    while (i < s.length) do
      c = s[i]

      if c == '<'
        if cur_tag
          s.slice!(i)

          next
        else
          cur_tag = String.new
          cur_tag_extras = nil
          is_end_tag = false
        end
      elsif c == '>'
        if cur_tag
          if cur_tag.length > 0
            if is_end_tag
              if cur_tag_extras and cur_tag_extras.strip.length > 0
                failure = true
                break
              elsif cur_tag == open_tags.last
                open_tags.pop
                cur_tag = nil
              else
                failure = true
                break
              end
            else
              if s[i-1] != '/'
                open_tags.push(cur_tag)
              end

              validate_attrs.call(cur_tag_extras)
              break if failure

              cur_tag = nil
            end
          else
            if is_end_tag
              s.slice!(i-2..i)
              i -= 2
            else
              s.slice!(i-1..i)
              i -= 1
            end

            cur_tag = nil
            next
          end
        else
          s.slice!(i)

          next
        end
      elsif c == ' ' and cur_tag and not cur_tag_extras
        cur_tag_extras = String.new
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

    failure = true if not open_tags.empty?
    failure = true if cur_tag

    if failure
      s = s.gsub(/<|>/, '')
    end

    s
  end
end
