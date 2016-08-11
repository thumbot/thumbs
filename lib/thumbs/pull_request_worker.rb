require 'http'
require 'log4r'
module Thumbs
  class PullRequestWorker
    include Log4r
    attr_reader :build_dir
    attr_reader :build_status
    attr_accessor :build_steps
    attr_reader :repo
    attr_reader :pr
    attr_reader :thumb_config
    attr_reader :log

    def initialize(options)
      self.class.authenticate_github
      @log=Log4r::Logger['mylog']
      @repo = options[:repo]
      @pr = Octokit.pull_request(options[:repo], options[:pr])
      @build_dir=options[:build_dir] || "/tmp/thumbs/#{@repo.gsub(/\//, '_')}_#{@pr.number}"
      @build_status={:steps => {}}
      @build_steps = [ "make", "make test" ]
      @thumb_config = { :minimum_reviewers => 2, :build_steps => @build_steps }
    end

    def cleanup_build_dir
      FileUtils.rm_rf(@build_dir)
    end

    def clone(dir=build_dir)
      g = Git.clone("git@github.com:#{@repo}", dir)
    end

    def try_merge

      pr_branch="feature_#{DateTime.now.strftime("%s")}"
      # find the target branch in the pr

      status={}
      status[:started_at]=DateTime.now
      cleanup_build_dir
      g = clone(@build_dir)
      load_thumbs_config
      begin
        g.checkout(@pr.head.sha)
        g.checkout(@pr.base.ref)
        g.branch(pr_branch).checkout
        log.debug "Trying merge #{@repo}:PR##{@pr.number} \" #{@pr.title}\" #{@pr.head.sha} onto #{@pr.base.ref}"
        merge_result = g.merge("#{@pr.head.sha}")
        status[:ended_at]=DateTime.now
        status[:result]=:ok
        status[:message]="Merge Success: #{@pr.head.sha} onto target branch: #{@pr.base.ref}"
        status[:output]=merge_result
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
      status={}

      command = "cd #{@build_dir} && #{command} 2>&1"
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
      status[:message] = message
      status[:command] = command
      status[:output] = output
      status[:exit_code] = $?.exitstatus

      @build_status[:steps][name.to_sym]=status
      log.debug "[ #{name.upcase} ] [#{result.upcase}] \"#{command}\""
      status
    end

    def comments
      client = Octokit::Client.new(:login => ENV['GITHUB_USER'], :password => ENV['GITHUB_PASS'])
      client.issue_comments(@repo, @pr.number)
    end

    def bot_comments
      comments.collect { |c| c if c[:user][:login] == ENV['GITHUB_USER'] }
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

    def validate
      cleanup_build_dir &&
      clone() &&
      try_merge

      build_steps.each do|build_step|
        try_run_build_step(build_step.gsub(/\s+/,'_').gsub(/-/,''), build_step)
      end
    end
    def merge
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
        status[:message]=".mergeable_state not clean"
        status[:ended_at]=DateTime.now
        return status
      end

      begin
        log.debug("PR ##{@pr.number} Starting github API merge request")
        client = Octokit::Client.new(:login => ENV['GITHUB_USER'], :password => ENV['GITHUB_PASS'])
        commit_message = 'Thumbs Git Robot Merge. '

        merge_response = client.merge_pull_request(@repo, @pr.number, commit_message, options = {})
        merge_comment="Successfully merged *#{@repo}/pulls/#{@pr.number}* (*#{@pr.head.sha}* on to *#{@pr.base.ref}*)\n\n"
        merge_comment << " ```yaml    \n#{merge_response.to_hash.to_yaml}\n ``` \n"

        add_comment merge_comment
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
      log=Log4r::Logger['mylog']
      log.debug("STATE: #{Octokit.pull_request(@repo, @pr.number).state}")
      Octokit.pull_request(@repo, @pr.number).state == "open"
    end

    def add_comment(comment)
      client = Octokit::Client.new(:login => ENV['GITHUB_USER'], :password => ENV['GITHUB_PASS'])
      client.add_comment(@repo, @pr.number, comment, options = {})
    end

    def close
      client = Octokit::Client.new(:login => ENV['GITHUB_USER'], :password => ENV['GITHUB_PASS'])
      client.close_pull_request(@repo, @pr.number)
    end

    def create_build_status_comment
      comment = render_template <<-EOS
#### Build Status:
Looks good @<%= @pr.user.login %>!  :+1:
<% @build_status[:steps].each do |step_name, status| %>
#### <%= result_image(status[:result]) %> <%= step_name.upcase %>   <%= status[:result].upcase %>
> Started at: <%= status[:started_at].strftime("%Y-%m-%d %H:%M") %>
> Duration: <%= status[:ended_at].strftime("%s").to_i-status[:started_at].strftime("%s").to_i %> seconds.
> Result:  <%= status[:result].upcase %>
> Message: <%= status[:message] %>
> Exit Code:  <%= status[:exit_code] || status[:result].upcase %>

```

<%= status[:command] %>

<%= status[:output] %>

```

--------------------------------------------------

<% end %>
      EOS
      add_comment(comment)
    end

    def create_reviewers_comment
      comment = render_template <<-EOS
<% reviewers=reviews.collect { |r| "*@" + r[:user][:login] + "*" } %>
Code reviews from: <%= reviewers.join(", ") %>.
##### Merging and closing this PR.
      EOS
      add_comment(comment)
    end

    private

    def render_template(template)
      ERB.new(template).result(binding)
    end

    def add_slack_message(channel, message)
      client = Slack::RealTime::Client.new

      rc = HTTP.post("https://slack.com/api/chat.postMessage", params: {
          token: ENV['SLACK_API_TOKEN'],
          channel: channel,
          text: message,
          as_user: true
      })
    end
    def self.authenticate_github
      Octokit.configure do |c|
        c.login = ENV['GITHUB_USER']
        c.password = ENV['GITHUB_PASS']
      end
    end
    def load_thumbs_config
      thumb_file = File.join(@build_dir, ".thumbs.yml")
      unless File.exist?(thumb_file)
        log.debug "\".thumbs.yml\" config file not found, using defaults"
        return false
      end
      begin
        @thumb_config=YAML.load(IO.read(thumb_file))
        @log.debug "\".thumbs.yml\" config file Loaded: #{@thumb_config.to_yaml}"
        return true
      rescue => e
        log.error "thumbs config file loading failed, using defaults"
      end
      false
    end
    def result_image(result)
      case result
        when :ok
          ":white_check_mark:"
        when :error
          ":no_entry:"
        else
          ""
      end
    end
  end
end
