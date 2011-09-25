# encoding: utf-8

class NilClass
  def value()   self end
  def key()     self end
  def next()    self end
  def [](*args) self end
  def empty?()  true end

  #def each_char(*args) self end
end
