#!/usr/bin/env ruby
# encoding: utf-8

Encoding.default_internal = 'utf-8'

BASE_PORT = 8080
MAX_SERVERS = 1 # Only one actually allowed with current ATH design (strings in memory)
LOG_FILE = './run/log'
PID_FILE = './run/pid'

stdout = $stdout
$stdout = File.open(LOG_FILE, 'a')

if File.exists?(PID_FILE) then
  stdout.puts "Error: #{PID_FILE} exists"
  exit 1
end

if not system("ps -C mongod >/dev/null")
  stdout.puts "Error: mongod does not appear to be running"
  exit 1
end

require 'rack'
require './ath.rb'

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
