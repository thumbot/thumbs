ENV['RACK_ENV'] = 'test'

$:.unshift(File.dirname(__FILE__))

require 'test_helper'
require 'test/test_basic_flow'
#require 'test/test_integrations'
#require 'test/test_webhook'
#require 'test/test_slack'
