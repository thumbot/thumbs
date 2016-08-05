module Thumbs
  MINIMUM_REVIEWERS=2

  def self.start_logger
    log = Logger.new 'mylog'
    formatter = PatternFormatter.new(:pattern => "[%l] %d :Thumbs: %1m")
    log.outputters = StdoutOutputter.new("console", :formatter => formatter)
    log.level = Log4r::DEBUG
  end
  def self.authenticate_github
    Octokit.configure do |c|
      c.login = ENV['GITHUB_USER']
      c.password = ENV['GITHUB_PASS']
    end
  end
  def process_payload(payload)
    [payload['repository']['full_name'], payload['issue']['number']]
  end

  class PullRequestWorker
    attr_reader :build_dir
    attr_reader :build_status
    attr_reader :repo
    attr_reader :pr
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
      log=Logger['mylog']

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
        log.debug "Trying merge #{@repo}:PR##{@pr.number} \" #{@pr.title}\" #{@pr.head.sha} onto #{target_branch}"
        g.merge("#{@pr.head.sha}")
        status[:ended_at]=DateTime.now
        status[:result]=:ok
        status[:message]="Merge Success"
      rescue StandardError => e
        log.error "Merge Failed"
        log.debug "PR ##{@pr[:number]} END"

        status[:result]=:error
        status[:message]="Merge test failed"
        status[:output]=e.inspect
      end

      @build_status[:steps][:merge]=status
      status
    end

    def try_run_build_step(name, command)
      log = Logger['mylog']

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
      log.debug "[ #{name.upcase} ] [#{result.upcase}] \"#{command}\""
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
      log = Logger['mylog']
      log.debug "determine valid_for_merge? #{@repo} #{@pr.number}"
      log_msg_head="#{@repo}##{@pr.number} valid_for_merge? "
      unless state == "open"
        log.debug "#{log_msg_head} state != open"
        return false
      end
      unless mergeable?
        log.debug "#{log_msg_head} != mergeable? "
        return false
      end
      unless mergeable_state == "clean"
        log.debug "#{log_msg_head} mergeable_state != clean #{mergeable_state} "
        return false
      end

      return false unless @build_status.key?(:steps)
      return false unless @build_status[:steps].key?(:merge)
      return false unless @build_status[:steps].key?(:build)
      return false unless @build_status[:steps].key?(:test)

      log.debug "passed initial"
      log.debug @pr.state
      @build_status[:steps].each_key do |name|
         unless @build_status[:steps][name].key?(:result)
           return false
         end
         unless @build_status[:steps][name][:result]==:ok
           log.debug "result not :ok, not valid for merge"
           return false
         end
      end
      log.debug "all keys and result ok present"
      log.debug "review_count: #{reviews.length} >= #{MINIMUM_REVIEWERS}"

      unless reviews.length >= MINIMUM_REVIEWERS
        log.debug " #{reviews.length} !>= #{MINIMUM_REVIEWERS}"
        return false
      end
      log.debug "#{@pr.number} valid_for_merge? TRUE"
      return true
    end

    def merge
      log = Logger['mylog']
      status={}
      status[:started_at]=DateTime.now
      if merged?
        log.debug "already merged ? nothing to do here"
        status[:result]=:error
        status[:message]="already merged"
        status[:ended_at]=DateTime.now
        return status
      end
      unless state == "open"
        log.debug "pr not open"
        status[:result]=:error
        status[:message]="pr not open"
        status[:ended_at]=DateTime.now
        return status
      end
      unless mergeable?
        log.debug "no mergeable? nothing to do here"
        status[:result]=:error
        status[:message]=".mergeable returns false"
        status[:ended_at]=DateTime.now
        return status
      end
      unless mergeable_state == "clean"

        log.debug ".mergeable_state not clean! "
        status[:result]=:error
        status[:message]=".mergeable returns false"
        status[:ended_at]=DateTime.now
        return status
      end

      begin
        log.debug("PR ##{@pr.number} Starting merge attempt")
        client = Octokit::Client.new(:login => ENV['GITHUB_USER1'], :password => ENV['GITHUB_PASS1'])
        commit_message = 'Thumbs Git Robot Merged. Looks good :+1: :+1: !'
        comment_message=""
        add_comment <<-EOS
Looks good! :+1:
Code reviews from: #{reviews.collect{|r| r[:user][:login]}.join(",")}
Merging and Closing this PR.
```
#{@build_status.to_json}
```
        EOS
        client.merge_pull_request(@repo, @pr.number, commit_message, options = {})
        log.debug "PR ##{@pr.number} Merge OK"
      rescue StandardError => e
        log_message = "PR ##{@pr.number} Merge FAILED #{e.inspect}"
        log.debug log_message

        status[:message] = log_message
        status[:output]=e.inspect
      end
      status[:ended_at]=DateTime.now

      log.debug "PR Merge ##{@pr[:number]} END"
      status
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
      log = Logger['mylog']
      log.debug("STATE: #{Octokit.pull_request(@repo, @pr.number).state}")
      Octokit.pull_request(@repo, @pr.number).state == "open"
    end
    def add_comment(comment)
      client = Octokit::Client.new
      client.add_comment(@repo, @pr.number, comment, options = {})
    end
  end
end