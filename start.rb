#!/usr/bin/env ruby

require 'rack'
require './ath.rb'

BASE_PORT = 8080
# Cached strings will be stale in all but the saving server when someone updates them,
#  so you can only have one server
MAX_SERVERS = 1
LOG_FILE = './run/log'
PID_FILE = './run/pid'

stdout = $stdout
$stdout = File.open(LOG_FILE, 'a')

if File.exists?(PID_FILE) then
  stdout.puts "Error: #{PID_FILE} exists"
  exit 1
end

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

servers.times do
  fork do
    stdout.puts "Starting server on port #{port} with PID #{$$}"

    File.open(PID_FILE, 'a') do |file|
      file.puts $$
    end
    
    Rack::Handler::Thin.run(AndroidTranslationHelper.new(), :Host => '127.0.0.1', :Port => port)
  end
  sleep 0.01

  port += 1
end

sleep 0.01
