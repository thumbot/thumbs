require 'yaml'
require 'log4r'
require 'octokit'
require 'git'
require 'erb'
require 'slack-ruby-client'

MINIMUM_REVIEWERS=2
CONFIGURED_SLACK_CHANNELS=%w[testing]

$:.unshift(File.dirname(__FILE__))

require 'thumbs/general_helpers'
require 'thumbs/webhook_helpers'
require 'thumbs/pull_request_worker'


