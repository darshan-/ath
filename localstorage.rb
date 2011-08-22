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

    oldwd = Dir.getwd()
    Dir.chdir(DIR_NAME)

    Dir.glob('*_*').each do |filename|
      langs << filename.split('_').first
    end

    Dir.chdir(oldwd)

    langs.uniq - ['en']
  end

  def get_strings(lang)
    return if not get_langs().include? lang

    oldwd = Dir.getwd()
    Dir.chdir(DIR_NAME)

    filename = Dir.glob("#{lang}_*").last
    string = ''
    File.open(filename) {|f| string = f.read()}

    Dir.chdir(oldwd)
    
    string
  end

  def put_strings(lang, strings_xml)
    oldwd = Dir.getwd()
    Dir.chdir(DIR_NAME)

    filename = Dir.glob("#{lang}_*").last.next || lang + '_000001'
    File.open(filename, 'w') {|f| f.write(strings_xml)}

    Dir.chdir(oldwd)
  end
end
