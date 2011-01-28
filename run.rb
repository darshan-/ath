#require 'rubygems'
require 'rack'
require './ath.rb'

port = 8080
i = ARGV[0].to_i
port += i if i > 0

Rack::Handler::Thin.run(AndroidTranslationHelper.new(), :Host => '127.0.0.1', :Port => port)
