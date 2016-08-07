ENV['RACK_ENV'] = 'test'

$:.unshift(File.join(File.dirname(__FILE__), '/../'))
require 'app'
require 'test/unit'
require 'rack/test'
require 'dust'
require 'test/test_integrations'
require 'test/test_webhook'
require 'test/test_slack'
