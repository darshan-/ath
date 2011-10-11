#!/usr/bin/env ruby
# encoding: utf-8

# These actually take a perceivable amount of time to load, so wait until you know you need them
def do_requires()
  require 'rack'
  require './lib/my_thin.rb'
  require './android_translation_helper.rb'
end

BASE_PORT = 8080
MAX_SERVERS = 1 # Only one actually allowed with current ATH design (strings in memory)

ATH_DIR  = File.dirname(File.dirname(File.realpath(__FILE__)))
RUN_DIR  = './run/'
LOG_FILE = './run/log'
PID_FILE = './run/pid'

Dir.chdir(ATH_DIR)

Encoding.default_internal = 'utf-8'

up = lambda do |argv = []|
  bad_usage() if argv.length > 1

  if argv[0]
    servers = argv[0].to_i

    if servers.zero?
      bad_usage()
    end
  end

  servers ||= 1

  if not live_pids().empty? then
    puts "Error: Already running"
    exit 1
  end

  if not system("ps -C mongod >/dev/null")
    puts "Error: mongod does not appear to be running"
    exit 1
  end

  system("mkdir -p #{RUN_DIR}")

  if servers > MAX_SERVERS then
    puts "Warning: #{servers} is greater than maximum of #{MAX_SERVERS}; starting only #{MAX_SERVERS} servers"
    servers = MAX_SERVERS
  end

  redirect_stdout()
  do_requires()

  port = BASE_PORT

  servers.times do
    start_server(port)
    port += 1
  end

  sleep 0.01
end

down = lambda do |argv = []|
  bad_usage() unless argv.empty?

  pids = live_pids()

  if pids.empty?
    puts "Warning: Not running; doing nothing."
    exit 1
  end

  pids.each do |pid, running|
    action = running ? "  Stopping" : "* Removing"
    puts "#{action} server with PID #{pid}"
    system("kill #{pid}") if running
  end
  
  File.delete(PID_FILE)
end

restart = lambda do |argv = []|
  bad_usage() unless argv.empty?

  pids = live_pids()

  if pids.empty?
    puts "Warning: No instances running; doing a fresh start rather than restart."
    up.call()
  else
    down.call()
    up.call([pids.length])
  end
end

status = lambda do |argv = []|
  bad_usage() unless argv.empty?

  pids = live_pids()

  if pids.empty?
    puts "Not running"
    exit
  end

  pids.each do |pid, running|
    status = running ? "  Running" : "* CRASHED"
    puts "#{status} with PID #{pid}"
  end
end

reload = lambda do |argv = []|
  bad_usage() unless argv.empty?

  system("wget --quiet -O /dev/null --ignore-length --post-data="" http://ath.localhost/bi/reload_text")

  if $?.exitstatus > 0
    puts "Something went wrong."
  else
    puts "Reloaded text."
  end
end

restart_crashed = lambda do |argv = []|
  bad_usage() unless argv.empty?

  pids = live_pids()
  return if pids.values.count(false).zero?

  redirect_stdout()
  do_requires()

  port = BASE_PORT

  File.delete(PID_FILE)

  pids.each do |pid, running|
    if running
      File.open(PID_FILE, 'a') do |file|
        file.puts pid
      end
    else
      puts "#{Time.now} Huh, the server on port #{port} seems to have crashed; restarting..."
      start_server(port)
    end

    port += 1
  end
end

def start_server(port)
  fork do
    $stderr.puts "Starting server on port #{port} with PID #{$$}"

    File.open(PID_FILE, 'a') do |file|
      file.puts $$
    end

    Rack::Handler::Thin.run(AndroidTranslationHelper.new(), :Host => '127.0.0.1', :Port => port)
  end

  sleep 0.01
end

def redirect_stdout()
  $stdout = File.open(LOG_FILE, 'a')
  $stdout.sync = true # So I can look at the logs while the app is running
end

def live_pids()
  a = {}

  return a if not File.exists?(PID_FILE)

  IO.readlines(PID_FILE).each do |line|
    pid = line.strip()
    c = `ps --no-heading -p #{pid} -o command`.strip.split

    a[pid] = (c.length > 1 and c[1] == __FILE__)
  end

  a
end

def bad_usage
  puts "Usage: #{File.basename($PROGRAM_NAME)} COMMAND [subcommands]"
  exit 1
end

commands = {'up'      => up,
            'start'   => up,
            'down'    => down,
            'stop'    => down,
            'restart' => restart,
            'reload'  => reload,
            'status'  => status,
            'uncrash' => restart_crashed}

if command = commands[ARGV.shift]
  command.call(ARGV)
else
  bad_usage()
end
