# encoding: utf-8

module StrHelper
  def self.quoted?(s)
    s[0] == '"' and s[s.length-1] == '"' and s.length > 2
  end

  def self.clean(s)
    s.gsub(/\s*\\n\s*/, '\n').gsub(/\s+/, ' ').gsub(/\\n/, "\\n\n").strip
  end
end
