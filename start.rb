#!/usr/bin/env ruby

require 'rack'
require './ath.rb'

stdout = $stdout
$stdout = File.new('run/log', 'a')

if not Dir.glob('run/pid*').empty? then
  stdout.puts "Error: some run/pid* exists"
  exit 1
end

BASE_PORT = 8080
MAX_SERVERS = 6

port = BASE_PORT

servers = ARGV[0].to_i

if servers < 1 then
  stdout.puts "Warning: '#{ARGV[0]}' not understood; starting 1 server" if ARGV[0]
  servers = 1
end

if servers > MAX_SERVERS then
  stdout.puts "Warning: #{servers} is greater than maximum of #{MAX_SERVERS}; starting only #{MAX_SERVERS} servers"
  servers = MAX_SERVERS
end

while servers > 0
  fork do
    stdout.puts "Starting server on port #{port} with PID #{$$}"

    pid_file = File.new('run/pid' << (port - BASE_PORT).to_s, 'w')
    pid_file.puts $$
    pid_file.close()
    
    Rack::Handler::Thin.run(AndroidTranslationHelper.new(), :Host => '127.0.0.1', :Port => port)
  end

  sleep 0.005

  port += 1
  servers -= 1
end

sleep 0.005
