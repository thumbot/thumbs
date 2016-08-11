$:.unshift(File.join(File.dirname(__FILE__), '/lib'))

require 'thumbs'
require 'sinatra/base'
require 'json'

class ThumbsWeb < Sinatra::Base
  helpers Sinatra::GeneralHelpers
  helpers Sinatra::WebhookHelpers

  post '/webhook' do
    log = start_logger


    payload = JSON.parse(request.body.read)
    log.debug("received webhook #{payload.to_yaml}")

    case payload_type(payload)
      when :new_pr
        repo, pr = process_payload(payload)
        log.debug "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo=>repo,:pr=>pr)
        log.debug("new pull request #{pr_worker.repo}/pulls/#{pr_worker.pr.number} ")
        pr_worker.validate
        pr_worker.create_build_status_comment
      when :new_comment
        repo, pr = process_payload(payload)
        log.debug "got repo #{repo} and pr #{pr}"
        pr_worker = Thumbs::PullRequestWorker.new(:repo=>repo,:pr=>pr)
        log.debug("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} #{payload['comment']['body']}")

        pr_worker.validate
        if pr_worker.valid_for_merge?
          log.debug("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? OK ")
          pr_worker.create_build_status_comment
          pr_worker.create_reviewers_comment
          pr_worker.merge
        else
          log.debug("new comment #{pr_worker.repo}/pulls/#{pr_worker.pr.number} valid_for_merge? returned False")
        end
      when :unregistered
        log.debug "This is not an event I recognize(new_pr, new_comment): ignoring"
    end
    "OK"
  end
end

