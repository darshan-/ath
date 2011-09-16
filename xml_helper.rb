require 'nokogiri'
require 'cgi'

class XMLHelper
  def self.xml_to_str(xml)
    strings = {}
    str_ars = {}
    str_pls = {}

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
        h[:quoted] = true
        s = s[1, s.length-2]
      end

      h[:string] = s

      h
    end

    doc = Nokogiri::XML(xml)

    doc.xpath('//string').each do |str_el|
      strings[str_el.attr('name')] = parse_string.call(str_el)
    end

    doc.xpath('//string-array').each do |sa_el|
      str_ars[sa_el.attr('name')] = []

      sa_el.element_children.each_with_index do |item_el, i|
        str_ars[sa_el.attr('name')][i] = parse_string.call(item_el)
      end
    end

    doc.xpath('//plurals').each do |sp_el|
      str_pls[sp_el.attr('name')] = {}

      sp_el.element_children.each do |item_el|
        str_pls[sp_el.attr('name')][item_el.attr('quantity')] = parse_string.call(item_el)
      end
    end

    { :strings => strings,
      :str_ars => str_ars,
      :str_pls => str_pls }
  end

  def self.str_to_xml(s)
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

    quote_or_clean = lambda do |s, quote|
      return %Q{"#{s}"} if quote

      s.gsub(/\r|\n/, '').gsub(/\s+/, ' ').strip
    end

    params.each do |key, value|
      next if value.empty?

      if value.is_a? Hash
        next if all_empty.call(value)

        if value.has_key? '0'
          str_ar = Nokogiri::XML::Node.new('string-array', doc)
          str_ar['name'] = key

          value.each do |i, v|
            item = Nokogiri::XML::Node.new('item', doc)
            item.content = quote_or_clean.call(escape_quotes.call(validate_tags(v)),
                                               @strings['en'][key][i][:quoted])
            str_ar.add_child(item)
          end

          res.add_child(str_ar)
        else
          str_pl = Nokogiri::XML::Node.new('plurals', doc)
          str_pl['name'] = key

          value.each do |q, v|
            next if v.empty?
            item = Nokogiri::XML::Node.new('item', doc)
            item['quantity'] = q
            item.content = quote_or_clean.call(escape_quotes.call(validate_tags(v)),
                                               @strings['en'][key][q][:quoted])
            str_pl.add_child(item)
          end

          res.add_child(str_pl)
        end
      else
        str = Nokogiri::XML::Node.new('string', doc)
        str['name'] = key
        str['formatted'] = 'false'
        str.content = quote_or_clean.call(escape_quotes.call(validate_tags(value)),
                                          @strings['en'][key][:quoted])
        res.add_child(str)
      end
    end

    CGI.unescapeHTML(doc.to_xml(:encoding => 'utf-8'))
  end
end
