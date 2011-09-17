# encoding: utf-8

require './dsts.rb'

class AthPage < XhtmlPage
  def initialize()
    super()
    @style_sheets = ['/ath/static/ath.css']
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
end
