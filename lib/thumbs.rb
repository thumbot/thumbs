module Thumbs
  MINIMUM_REVIEWERS=2

  def process_payload(payload)
    [payload['repository']['full_name'], payload['issue']['number']]
  end

  class PullRequestWorker
    attr_reader :build_dir
    attr_reader :build_status
    def initialize(options)
      @repo = options[:repo]
      @pr = Octokit.pull_request(options[:repo], options[:pr])
      @build_dir=options[:build_dir] || "/tmp/thumbs/#{@repo.gsub(/\//, '_')}_#{@pr.number}"
      @build_status={:steps => {}}
    end

    def cleanup_build_dir
      FileUtils.rm_rf(@build_dir)
    end

    def clone(dir=build_dir)
      g = Git.clone("git@github.com:#{@repo}", dir)
    end

    def try_merge
      mylogger=Logger['mylog']

      pr_branch="feature_#{DateTime.now.strftime("%s")}"
      target_branch='master'

      status={}
      status[:started_at]=DateTime.now
      cleanup_build_dir
      g = clone(@build_dir)
      begin
        g.checkout(@pr.head.sha)
        g.checkout(target_branch)
        g.branch(pr_branch).checkout
        mylogger.debug "Trying merge #{@repo}:PR##{@pr.number} \" #{@pr.title}\" #{@pr.head.sha} onto #{target_branch}"
        g.merge("#{@pr.head.sha}")
        status[:ended_at]=DateTime.now
        status[:result]=:ok
        status[:message]="Merge Success"
      rescue StandardError => e
        mylogger.error "Merge Failed"
        mylogger.debug "PR ##{@pr[:number]} END"

        status[:result]=:error
        status[:message]="Merge test failed"
        status[:output]=e.inspect
      end

      @build_status[:steps][:merge]=status
      status
    end

    def try_run_build_step(name, command)
      mylogger = Logger['mylog']

      status={}

      command = "cd #{@build_dir} && #{command}"
      status[:started_at]=DateTime.now
      output = `#{command}`
      status[:ended_at]=DateTime.now

      unless $? == 0
        result = :error
        message = "Step #{name} Failed!"
      else
        result = :ok
        message = "OK"
      end
      status[:result] = result
      status[:message] = message,
          status[:command] = command,
          status[:output] = output,
          status[:exit_code] = $?.exitstatus

      @build_status[:steps][name.to_sym]=status
      mylogger.debug "[ #{name.upcase} ] [#{result.upcase}] \"#{command}\""
      status
    end

    def comments
      o=Octokit::Client.new
      o.issue_comments(@repo, @pr.number)
    end

    def contains_plus_one?(comment_body)
      comment_body =~ /\+1/
    end

    def non_author_comments
      comments.collect { |comment| comment unless @pr[:user][:login] == comment[:user][:login] }.compact
    end

    def reviews
      non_author_comments.collect { |comment| comment if contains_plus_one?(comment[:body]) }.compact
    end

    def valid_for_merge?
      mylogger = Logger['mylog']
      mylogger.debug "determine valid_for_merge? #{@repo} #{@pr.number}"
      return false unless @build_status.key?(:steps)
      return false unless @build_status[:steps].key?(:merge)
      return false unless @build_status[:steps].key?(:build)
      return false unless @build_status[:steps].key?(:test)
      mylogger.debug "passed initial"
      mylogger.debug @pr.state
      @build_status[:steps].each_key do |name|
         unless @build_status[:steps][name].key?(:result)
           return false
         end
         unless @build_status[:steps][name][:result]==:ok
           mylogger.debug "result not :ok, not valid for merge"
           return false
         end
      end
      mylogger.debug "all keys and result ok present"
      mylogger.debug "review_count: #{reviews.length} >= #{MINIMUM_REVIEWERS}"

      unless reviews.length >= MINIMUM_REVIEWERS
        mylogger.debug " #{reviews.length} !>= #{MINIMUM_REVIEWERS}"
        return false
      end

      true
    end

    def merge
      mylogger = Logger['mylog']
      status={}
      status[:started_at]=DateTime.now
      if merged?
        mylogger.debug "already merged ? nothing to do here"
        status[:result]=:error
        status[:message]="already merged"
        status[:ended_at]=DateTime.now
        return status
      end
      unless state == "open"
        mylogger.debug "pr not open"
        status[:result]=:error
        status[:message]="pr not open"
        status[:ended_at]=DateTime.now
        return status
      end
      unless mergeable?
        mylogger.debug "no mergeable? nothing to do here"
        status[:result]=:error
        status[:message]=".mergeable returns false"
        status[:ended_at]=DateTime.now
        return status
      end
      unless mergeable_state == "clean"

        mylogger.debug ".mergeable_state not clean! "
        status[:result]=:error
        status[:message]=".mergeable returns false"
        status[:ended_at]=DateTime.now
        return status
      end

      begin
        mylogger.debug("PR ##{@pr.number} Starting merge attempt")
        client = Octokit::Client.new(:login => ENV['GITHUB_USER1'], :password => ENV['GITHUB_PASS1'])
        client.merge_pull_request(@repo, @pr.number, commit_message = 'Thumbs Git Robot Merged. Looks good :+1: :+1: !', options = {})
        mylogger.debug "PR ##{@pr.number} Merge OK"
      rescue StandardError => e
        log_message = "PR ##{@pr.number} Merge FAILED #{e.inspect}"
        mylogger.debug log_message

        status[:message] = log_message
        status[:output]=e.inspect
      end
      status[:ended_at]=DateTime.now

      mylogger.debug "PR Merge ##{@pr[:number]} END"
      return status
    end
    def mergeable?
      Octokit.pull_request(@repo, @pr.number).mergeable
    end
    def mergeable_state
      Octokit.pull_request(@repo, @pr.number).mergeable_state
    end
    def merged?
      Octokit::Client.new.pull_merged?(@repo, @pr.number)
    end
    def state
      Octokit.pull_request(@repo, @pr.number).state
    end
    def open?
      mylogger = Logger['mylog']
      mylogger.debug("STATE: #{Octokit.pull_request(@repo, @pr.number).state}")
      Octokit.pull_request(@repo, @pr.number).state == "open"
    end
  end
end