# encoding: utf-8

module StrHelper
  # Note that the way I'm currently doing this, if I upload an XML
  # file that starts and ends with escaped double quotes -- so it's
  # not a quoted string to Android -- it will become quoted on the way
  # back out.  I think that's fine but worth noting.
  def self.quoted?(s)
    s[0] == '"' and s[s.length-1] == '"'
  end

  # TODO: What exactly does quoting a string in Android do? Obviously
  # it preserves leading or trailing spaces, but does it condense
  # multliple spaces down to one?  Does it preserve newlines?

  def self.clean(s)
    s.gsub(/\s*\\n\s*/, '\n').gsub(/\s+/, ' ').gsub(/\\n/, "\\n\n")
  end
end
