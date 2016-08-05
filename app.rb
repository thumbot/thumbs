require 'sinatra'
require 'json'
require 'yaml'
require 'log4r'
include Log4r
require 'octokit'
require 'git'
require 'erb'

$:.unshift(File.join(File.dirname(__FILE__), '/lib'))
require 'thumbs'

Thumbs.start_logger
Thumbs.authenticate_github

include Thumbs

get '/' do
  "Hi, nothing to see here"
end

post '/webhook' do
  payload = JSON.parse(request.body.read)
  log = Logger['mylog']
  #log.debug("received webhook #{payload.to_yaml}")

  unless payload.key?('issue')
    log.debug "this is not a comment event, ignoring "
    return "OK"
  end
  repo, pr_number = process_payload(payload)
  pr_worker=PullRequestWorker.new(:repo=>repo,:pr=>pr_number)


  pr_worker.cleanup_build_dir &&
  pr_worker.clone() &&
  pr_worker.try_merge &&
  pr_worker.try_run_build_step("build", "make build") &&
  pr_worker.try_run_build_step("test", "make test")

  if pr_worker.valid_for_merge?
    pr_worker.merge
  end
  #log.debug pr_worker.build_status.to_yaml
  "OK"
end