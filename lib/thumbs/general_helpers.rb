require 'sinatra/base'

module Sinatra
  module GeneralHelpers
    def start_logger
      log = Log4r::Logger.new 'mylog'
      formatter = Log4r::PatternFormatter.new(:pattern => "[%l] %d :Thumbs: %1m")
      log.outputters = Log4r::StdoutOutputter.new("console", :formatter => formatter)
      log.level = Log4r::DEBUG
    end

    def authenticate_slack
      Slack.configure do |config|
        config.token = ENV['SLACK_API_TOKEN']
        fail 'Missing ENV[SLACK_API_TOKEN]!' unless config.token
      end
    end

  end
end
