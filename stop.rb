#!/usr/bin/env ruby

PID_FILE = './run/pid'

if not File.exists?(PID_FILE) then
  puts "Error: #{PID_FILE} does not exist"
  exit 1
end

File.open(PID_FILE, 'r') do |file|
  file.each_line do |line|
    pid = line.strip()
    puts "Stopping server with PID #{pid}"
    system("kill #{pid}")
  end
end
    
File.delete(PID_FILE)
