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
    pr_worker = Thumbs::PullRequestWorker.new(:repo => TEST_PR.base.repo.full_name, :pr => TEST_PR.number)
    assert_false pr_worker.valid_for_merge?

    pr_worker.cleanup_build_dir
    pr_worker.clone
    pr_worker.try_merge
    pr_worker.try_run_build_step("build", "make build")
    pr_worker.try_run_build_step("test", "make test")

    assert_true pr_worker.valid_for_merge?, pr_worker.build_status

    pr_worker.merge

    pr = Octokit.pull_request(TEST_PR.base.repo.full_name, TEST_PR.number)
    assert pr.state == "closed"
    assert_equal pr.title, TEST_PR.title
  end
end
