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

def test_webhook_unmergable_pr
  post '/webhook', COMMENT_PAYLOAD.to_json
  assert last_response.body.include?("OK")
end

def test_webhook_mergeable_pr
  test_pr_worker=create_test_pr("BashoOps/prtester")

  sample_payload = {
      :repository => { :full_name => test_pr_worker.repo},
      :issue => { :number => test_pr_worker.pr.number }
  }

  post '/webhook', sample_payload.to_json

  assert last_response.body.include?("OK")

  assert_true test_pr_worker.open?
  assert test_pr_worker.reviews.length == 0

  create_test_code_reviews(test_pr_worker.repo, test_pr_worker.pr.number)

  assert test_pr_worker.reviews.length >= 2
  post '/webhook', sample_payload.to_json
  assert last_response.body.include?("OK")

  assert_false test_pr_worker.open?

end
  # to test

 #  post minimum payload for initial pull request creation.
  # when received, it will check the pr and count the comments to determine what stage we're in.
  # if count == 1, build status has been posted. or use a tag inside comment like build_step:1
  # if count == 2, build_status has been posted and  reviews have been made and merge request is in progess.
  # if count == 3, build is finished, merged.

end
