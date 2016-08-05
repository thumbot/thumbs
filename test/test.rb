ENV['RACK_ENV'] = 'test'

$:.unshift(File.join(File.dirname(__FILE__), '/../'))
require 'app'
require 'test/unit'
require 'rack/test'
require 'dust'
require 'test/test_integrations'
COMMENT_PAYLOAD = YAML.load(IO.read(File.join( File.expand_path(File.dirname('__FILE__'), './test/data/new_comment_payload.yml'))))


TEST_PR=create_test_pr("davidx/prtester")

class HelloWorldTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Thumbs
  def app
    Sinatra::Application
  end

  def test_basic_hello
    get '/'
    assert last_response.ok?
    assert_equal 'Hi, nothing to see here', last_response.body
  end

  def test_webhook
    post '/webhook', COMMENT_PAYLOAD.to_json
    assert last_response.body.include?("OK")
  end

  def test_webhook_mergeable_pr
    sample_payload = {
        :repository => { :full_name => TEST_PR.base.repo.full_name},
        :issue => { :number => TEST_PR.number }
    }
    post '/webhook', sample_payload.to_json

    assert last_response.body.include?("OK")
    pr_worker=Thumbs::PullRequestWorker.new(:repo => TEST_PR.base.repo.full_name, :pr => TEST_PR.number)

    if pr_worker.valid_for_merge?
      pr_worker.merge
    end

    p pr_worker.state
  end
end
