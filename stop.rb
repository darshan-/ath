#!/usr/bin/env ruby

pid_files = Dir.glob('run/pid*')

if pid_files.empty? then
  puts "Error: no run/pid* exists"
  exit 1
end

pid_files.each do |file_name|
  f = File.open(file_name, 'r')
  pid = f.gets.strip
  f.close()

  puts "Stopping server with PID #{pid}"
  system("kill #{pid}")

  File.delete(file_name)
end

#system('rm run/pid*')
