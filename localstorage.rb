class NilClass
  def value()   self end
  def key()     self end
  def next()    self end
  def [](*args) self end
  def empty?()  true end
end

class LocalStorage
  DIR_NAME = 'tmp-local-storage'

  def initialize()
    system("mkdir -p #{DIR_NAME}")
  end

  def get_langs()
    langs = []

    in_dir do
      Dir.glob('*_*').each do |filename|
        langs << filename.split('_').first
      end
    end

    langs.uniq - ['en']
  end

  def get_strings(lang)
    string = ''

    in_dir do
      filename = Dir.glob("#{lang}_*").sort.last
      File.open(filename) {|f| string = f.read()}
    end

    string
  end

  def put_strings(lang, strings_xml)
    in_dir do
      filename = Dir.glob("#{lang}_*").last.next || lang + '_000001'
      File.open(filename, 'w') {|f| f.write(strings_xml)}
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
