#!/usr/bin/env ruby

if Dir.glob('run/pid*').empty? then
  stdout.puts "Error: no run/pid* exists"
  exit 1
end

system('kill `cat run/pid*`')
system('rm run/pid*')
