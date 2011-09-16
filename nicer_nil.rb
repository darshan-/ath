class NilClass
  def value()   self end
  def key()     self end
  def next()    self end
  def [](*args) self end
  def empty?()  true end
end
