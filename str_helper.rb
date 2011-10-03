# encoding: utf-8

module StrHelper
  extend self # So methods don't have to be defined with self.method_name

  def quoted?(s)
    s[0] == '"' and s[s.length-1] == '"' and s.length > 2
  end

  def clean(s)
    s.gsub(/\s*\\n\s*/, '\n').gsub(/\s+/, ' ').gsub(/\\n/, "\\n\n").strip
  end
end
