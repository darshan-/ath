require 'thin'

module Thin
  class Connection
    def handle_error
      e = $!
      $stderr.puts "\nError: #{e.message}\n" + e.backtrace.join("\n")
      close_connection rescue nil
    end
  end
end
