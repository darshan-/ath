# encoding: utf-8

require './xml_helper.rb'
require './lib/nicer_nil.rb'

class LocalStorage
  DIR_NAME = 'tmp-local-storage'

  def initialize()
    system("mkdir -p #{DIR_NAME}")
  end

  def get_langs()
    langs = []

    in_dir do
      Dir.glob('*_*').to_a.each do |filename|
        langs << filename.split('_').first
      end
    end

    langs.uniq - ['en']
  end

  def get_strings(lang)
    xml_str = ''

    in_dir do
      filename = Dir.glob("#{lang}_*").sort.last
      File.open(filename) {|f| xml_str = f.read()}
    end

    XMLHelper.xml_to_str(xml_str)
  end

  def put_strings(lang, strings)
    xml_str = XMLHelper.str_to_xml(strings)
    in_dir do
      filename = Dir.glob("#{lang}_*").sort.last.next || lang + '_000001'
      File.open(filename, 'w') {|f| f.write(xml_str)}
    end
  end

  private

  def in_dir
    oldwd = Dir.getwd()
    Dir.chdir(DIR_NAME)

    begin
      yield
    rescue
    end

    Dir.chdir(oldwd)
  end
end
