ENV['RACK_ENV'] = 'test'

$:.unshift(File.join(File.dirname(__FILE__), '/../'))
require 'app'
require 'test/unit'
require 'rack/test'
require 'dust'

COMMENT_PAYLOAD = YAML.load(IO.read(File.join( File.expand_path(File.dirname('__FILE__'), './test/data/new_comment_payload.yml'))))

def create_test_pr(repo_name)
  # prep test data
  build_dir='/tmp/thumbs'
  FileUtils.mkdir_p(build_dir)
  test_dir="/tmp/thumbs/#{repo_name.gsub(/\//, '_')}_#{DateTime.now.strftime("%s")}"
  FileUtils.rm_rf(test_dir)

  g = Git.clone("git@github.com:#{repo_name}", test_dir)
  g.checkout('master')
  pr_branch="feature_#{DateTime.now.strftime("%s")}"
  File.open("#{test_dir}/testfile1", "a") do |f|
    f.syswrite(DateTime.now.to_s)
  end

  g.add(:all => true)
  g.commit_all("creating for test PR")
  g.branch(pr_branch).checkout
  g.repack
  system("cd #{test_dir} && git push -q origin #{pr_branch}")
  client1 = Octokit::Client.new(:login => ENV['GITHUB_USER'], :password => ENV['GITHUB_PASS'])
  pr = client1.create_pull_request(repo_name, "master", pr_branch, "Testing PR", "Thumbs Git Robot: This pr has been created for testing purposes")
  prw=Thumbs::PullRequestWorker.new(:repo=>repo_name, :pr=>pr.number)

  prw
end

def create_test_code_reviews(test_repo, pr_number)
  client1 = Octokit::Client.new(:login => ENV['GITHUB_USER'], :password => ENV['GITHUB_PASS'])
  client1.add_comment(test_repo, pr_number, "I think this is pretty sweet!", options = {})
  client2 = Octokit::Client.new(:login => ENV['GITHUB_USER2'], :password => ENV['GITHUB_PASS2'])
  client2.add_comment(test_repo, pr_number, "YAAAAAAAASSSS +1", options = {})
  client3 = Octokit::Client.new(:login => ENV['GITHUB_USER3'], :password => ENV['GITHUB_PASS3'])
  client3.add_comment(test_repo, pr_number, "Looks good +1", options = {})
end
