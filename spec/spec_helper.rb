$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

ENV['RACK_ENV'] = 'test'
require 'rspec'
require 'rack/test'
require 'sentinel'

RSpec.configure do |conf|
  conf.include Rack::Test::Methods
end
