require 'sinatra/base'

module Sinatra
  module WebhookHelpers
    def payload_type(payload)
      if payload.key?('pull_request') && payload['pull_request'].key?('number')
        return :new_pr
      end
      if payload.key?('comment') && payload.key?('issue') && payload['comment'].key?('body')
        return :new_comment
      end
      :unregistered
    end

    def process_payload(payload)
      case payload_type(payload)
        when :new_pr
          [payload['repository']['full_name'], payload['pull_request']['number']]
        when :new_comment
          [payload['repository']['full_name'], payload['issue']['number']]
        when :unregistered
          nil
      end
    end
  end
end
