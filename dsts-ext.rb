# encoding: utf-8

require './lib/dsts.rb'

class AthPage < XhtmlPage
  TA_COLS = 80 # How many columns to use for the strings' textareas

  def initialize(gecko_p = false)
    super()
    @style_sheets = ['/ath/static/ath.css']
    @gecko_p = gecko_p
  end

  def open_body()
    super()

    @page << %Q{<div id="centered_page_wrapper">}
    @page << %Q{<div class="main_box">}
  end

  def close_body()
    @page << %Q{</div></div>}
    super()
  end

  def add_trans_str_section(name, fields, options)
    frags = {}
    unless options[:no_anchor]
      anchor_name = name.gsub(/\[|\]/, '')
      frags[:anchor] = %Q{<a name="#{anchor_name}">}
      frags[:end_a] = '</a>'
      frags[:submit_name] = %Q{name="_ath_submit_#{anchor_name}" }
    end

    add %Q{<hr><div>#{frags[:anchor]}<b>#{name}#{'*' if options[:quoted]}</b>#{frags[:end_a]}}
    add %Q{<input style="float: right;" type="submit" #{frags[:submit_name]}value="Save All" /></div>\n}

    default_n_rows = nil
    fields.each do |label, content|
      n_rows = count_rows(content) || default_n_rows || 1
      default_n_rows ||= n_rows

      gecko_hack = ''
      gecko_hack = %Q{ style="height: #{n_rows * 1.3}em;"} if @gecko_p

      ta_frags = {}
      if label == fields.keys.last
        ta_frags[:name] = %Q{name="#{name}" }
      else
        ta_frags[:disabled] = %Q{ readonly="readonly"}
      end

      add %Q{#{label}:<br />\n<textarea #{ta_frags[:name]}}
      add %Q{cols="#{TA_COLS}" rows="#{n_rows}"#{gecko_hack}#{ta_frags[:disabled]}>#{content}</textarea><br />\n}
    end

    if options[:quoted] then
      add %Q{<br />*<i>Spaces at the beginning and/or end of this one are important.</i> }
      add %Q{<b>Be sure to match the original</b> (unless you really should do something different in your language).}
    end
  end

  private

  # Doesn't account for words that don't fit at the end starting new lines, but gets plenty close for now
  def count_rows(s)
    return nil if s.nil?

    col = 1
    row = 1

    s.each_char do |c|
      if c == "\n" or col > TA_COLS then
        col = 1
        row += 1
        next
      end

      col += 1
    end

    row
  end
end
