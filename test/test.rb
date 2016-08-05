ENV['RACK_ENV'] = 'test'

$:.unshift(File.join(File.dirname(__FILE__), '/../'))
require 'app'
require 'test/unit'
require 'rack/test'
require 'dust'
require 'test/test_integrations'
COMMENT_PAYLOAD = YAML.load(IO.read(File.join( File.expand_path(File.dirname('__FILE__'), './test/data/new_comment_payload.yml'))))


def create_test_pr_environment
  # prep test data
  build_dir='/tmp/thumbs'
  test_repo='davidx/prtester'
  test_dir="/tmp/thumbs/#{test_repo.gsub(/\//, '_')}_#{DateTime.now.strftime("%s")}"

  FileUtils.rm_rf(build_dir)
  FileUtils.mkdir_p(build_dir)

  FileUtils.rm_rf(test_dir)

  g = Git.clone("git@github.com:#{test_repo}", test_dir)

  g.checkout('master')
  pr_branch="feature_#{DateTime.now.strftime("%s")}"
  File.open("#{test_dir}/testfile1", "a") do |f|
    f.syswrite(DateTime.now.to_s)
  end

  #g.add(:all => true)
  g.commit_all("creating for test PR")
  g.branch(pr_branch).checkout

 # g.repack
  system("cd #{test_dir} && git push origin #{pr_branch}")
  client1 = Octokit::Client.new(:login => ENV['GITHUB_USER1'], :password => ENV['GITHUB_PASS1'])
  pr = client1.create_pull_request(test_repo, "master", pr_branch, "Testing PR", "Thumbs Git Robot: This pr has been created for testing purposes")
  client1.add_comment(test_repo, pr[:number], "I think this is pretty sweet!", options = {})
  client2 = Octokit::Client.new(:login => ENV['GITHUB_USER2'], :password => ENV['GITHUB_PASS2'])
  client2.add_comment(test_repo, pr[:number], "YAAAAAAAASSSS +1", options = {})
  client3 = Octokit::Client.new(:login => ENV['GITHUB_USER3'], :password => ENV['GITHUB_PASS3'])
  client3.add_comment(test_repo, pr[:number], "Looks good +1", options = {})
  pr
end

TEST_PR=create_test_pr_environment

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
