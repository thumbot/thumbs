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
  system("cd #{test_dir} && git push origin #{pr_branch}")
  client1 = Octokit::Client.new(:login => ENV['GITHUB_USER1'], :password => ENV['GITHUB_PASS1'])
  pr = client1.create_pull_request(repo_name, "master", pr_branch, "Testing PR", "Thumbs Git Robot: This pr has been created for testing purposes")
  pr
end


unit_tests do

  test "can try pr merge" do
    repo_name = TEST_PR.base.repo.full_name
    pr_number = TEST_PR.number

    pr = Thumbs::PullRequestWorker.new(:repo => repo_name, :pr => pr_number)
    assert pr.kind_of?(Thumbs::PullRequestWorker)

    assert pr.respond_to?(:try_merge)
    status = pr.try_merge

    assert status.key?(:result)
    assert status.key?(:message)

    assert_equal :ok, status[:result]

    status = pr.try_run_build_step("uptime", "uptime")

    assert status.key?(:exit_code)
    assert status.key?(:result)
    assert status.key?(:message)
    assert status.key?(:command)
    assert status.key?(:output)

    assert status.key?(:exit_code)
    assert status[:exit_code]==0
    assert status.key?(:result)
    assert status[:result]==:ok

    status = pr.try_run_build_step("uptime", "uptime -ewkjfdew 2>&1")

    assert status.key?(:exit_code)
    assert status.key?(:result)
    assert status.key?(:message)
    assert status.key?(:command)
    assert status.key?(:output)

    assert status.key?(:exit_code)
    assert status[:exit_code]==1
    assert status.key?(:result)
    assert status[:result]==:error

    status = pr.try_run_build_step("build", "make build")

    assert status.key?(:exit_code)
    assert status.key?(:result)
    assert status.key?(:message)
    assert status.key?(:command)
    assert status.key?(:output)

    assert status.key?(:exit_code)
    assert status[:exit_code]==0
    assert status.key?(:result)
    assert status[:result]==:ok

    assert_equal "cd /tmp/thumbs/#{TEST_PR.base.repo.full_name.gsub(/\//, '_')}_#{TEST_PR.number} && make build", status[:command]
    assert_equal "BUILD OK\n", status[:output]

    status = pr.try_run_build_step("test", "make test")

    assert status.key?(:exit_code)
    assert status.key?(:result)
    assert status.key?(:message)
    assert status.key?(:command)
    assert status.key?(:output)

    assert_equal "TEST OK\n", status[:output]
    assert status.key?(:exit_code)
    assert status[:exit_code]==0
    assert status.key?(:result)
    assert status[:result]==:ok

  end
  test "should pr be merged" do
    pr = Thumbs::PullRequestWorker.new(:repo => TEST_PR.base.repo.full_name, :pr => TEST_PR.number)
    assert pr.respond_to?(:reviews)

    assert pr.respond_to?(:valid_for_merge?)

  end

  test "merge pr" do
    test_pr=create_test_pr("davidx/prtester")

    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr.base.repo.full_name, :pr => test_pr.number)
    assert pr_worker.reviews.length == 0

    assert_false pr_worker.valid_for_merge?
    create_test_code_reviews("davidx/prtester", test_pr.number)

    assert pr_worker.reviews.length == 2

    pr_worker.cleanup_build_dir &&
    pr_worker.clone &&
    pr_worker.try_merge &&
    pr_worker.try_run_build_step("build", "make build")
    pr_worker.try_run_build_step("test", "make test")

    assert_true pr_worker.valid_for_merge?, pr_worker.build_status

    pr_worker.merge

    sleep 5
    prw2 = Thumbs::PullRequestWorker.new(:repo => test_pr.base.repo.full_name, :pr => test_pr.number)

    assert prw2.kind_of?(Thumbs::PullRequestWorker), prw2.inspect

    assert_equal "davidx/prtester", prw2.repo
    assert_false prw2.valid_for_merge?
    assert_false prw2.open?

  end

  test "add comment" do
    client1 = Octokit::Client.new(:login => ENV['GITHUB_USER1'], :password => ENV['GITHUB_PASS1'])

    test_pr = create_test_pr("davidx/prtester")
    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr.base.repo.full_name, :pr => test_pr.number)
    comments_list = pr_worker.comments

    client1.add_comment(test_pr.base.repo.full_name, test_pr.number, "Adding", options = {})

    pr_worker.add_comment("comment")

    pr_worker = Thumbs::PullRequestWorker.new(:repo => test_pr.base.repo.full_name, :pr => test_pr.number)

    new_comments_list = pr_worker.comments
    assert new_comments_list.length > comments_list.length

  end
  def create_test_code_reviews(test_repo, pr_number)
    client1 = Octokit::Client.new(:login => ENV['GITHUB_USER1'], :password => ENV['GITHUB_PASS1'])
    client1.add_comment(test_repo, pr_number, "I think this is pretty sweet!", options = {})
    client2 = Octokit::Client.new(:login => ENV['GITHUB_USER2'], :password => ENV['GITHUB_PASS2'])
    client2.add_comment(test_repo, pr_number, "YAAAAAAAASSSS +1", options = {})
    client3 = Octokit::Client.new(:login => ENV['GITHUB_USER3'], :password => ENV['GITHUB_PASS3'])
    client3.add_comment(test_repo, pr_number, "Looks good +1", options = {})
  end
end
