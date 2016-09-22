require "sentinel/version"
require "sinatra"
require "json"
require "pp"
require "openssl"
require "toml"
require "celluloid/current"
require "mixlib/shellout"
require "github_api"
require "openssl"
require "base64"
require "faraday"

module Sentinel
  def self.github
    Github.new do |cfg|
      cfg.client_id = CONFIG["cfg"]["login"]
      cfg.oauth_token = CONFIG["cfg"]["access_token"]
    end
  end

  class Git
    class << self
      def env
        { "GIT_SSH_COMMAND" => "ssh -i #{CONFIG["cfg"]["ssh_private_key"]} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" }
      end

      def clone(url, path)
        if ! Dir.exists?(path)
          puts "Cloning repository #{path} from #{url}"
          clone = Mixlib::ShellOut.new("git clone #{url} #{path}", :env => self.env)
          clone.run_command
          clone.error!
        else
          puts "Not cloning existing repository #{path}"
        end
      end

      def checkout(path, branch)
        puts "Checking out #{branch} for #{path}"
        cmd = Mixlib::ShellOut.new("git checkout #{branch}", :cwd => path)
        cmd.run_command
        cmd.error!
      end

      def branch(path, branch)
        puts "Creating #{branch} for #{path}"
        cmd = Mixlib::ShellOut.new("git checkout -b #{branch}", :cwd => path)
        cmd.run_command
        begin
          cmd.error!
        rescue
          checkout(path, branch)
        end
      end

      def fetch(path, number)
        puts "Fetching the merge commit"
        cmd = Mixlib::ShellOut.new("git fetch origin pull/#{number}/merge", :env => self.env, :cwd => path)
        cmd.run_command
        cmd.error!
      end

      def reset(path, sha)
        puts "Resetting to #{sha}"
        cmd = Mixlib::ShellOut.new("git reset --hard #{sha}", :cwd => path)
        cmd.run_command
        cmd.error!
      end

      def merge(path, pr, ref)
        puts "Merging #{ref}"
        cmd = Mixlib::ShellOut.new("git merge --no-ff -m 'The Sentinels Auto Testing PR ##{pr.number} SHA #{pr.head.sha}' #{ref}", :cwd => path)
        cmd.run_command
        cmd.error!
      end

      def push(path, ref)
        puts "Pushing #{ref}"
        cmd = Mixlib::ShellOut.new("git push --force origin #{ref}", :env => self.env, :cwd => path)
        cmd.run_command
        cmd.error!
      end

    end
  end

  class Processor
    include Celluloid

    def test(pr)
      name = pr.base.repo.name
      path = File.join(CACHE, name)
      begin
        Sentinel.github.issues.comments.create(
          pr.base.user.login,
          pr.base.repo.name,
          pr.number,
          body: ":metal: I am testing your branch against #{pr.base.ref} before merging it. We do this to ensure that the master branch is never failing tests."
        )
        Sentinel::Git.clone(pr.base.repo.ssh_url, path)
        Sentinel::Git.checkout(path, "master")
        Sentinel::Git.fetch(path, pr.number)
        Sentinel::Git.branch(path, "sentinel/#{pr.base.user.login}/#{pr.base.repo.name}/#{pr.number}")
        Sentinel::Git.reset(path, pr.merge_commit_sha)
        Sentinel::Git.push(path, "sentinel/#{pr.base.user.login}/#{pr.base.repo.name}/#{pr.number}")
      rescue => e
        Sentinel.github.issues.comments.create(
          pr.base.user.login,
          pr.base.repo.name,
          pr.number,
          body: "Sorry; I had a problem testing this pull request. The error was:\n\n```ruby\n#{e}\n```\n\n![Oops](https://cloud.githubusercontent.com/assets/4304/17756537/583f4ba4-6495-11e6-97c8-0c22ceaf7e63.gif)"
        )
      end
    end
  end

  class Hub
    class << self
      def opened_pr(pr)
        puts "Opening #{pr["pull_request"]["head"]["repo"]["name"]} ##{pr["number"]}; status is pending"

        Sentinel.github.issues.comments.create(
          pr["repository"]["owner"]["login"],
          pr["repository"]["name"],
          pr["pull_request"]["number"],
          body: "Thanks for the pull request! Here is what will happen next:\n 1. Your PR will be reviewed by the maintainers\n 2. If everything looks good, one of them will `approve` it, and your PR will be merged.\n\nThank you for contributing!")
      end

      def authenticated?(pr, command)
        if CONFIG["cfg"]["repo"][pr["repository"]["name"]]["approvers"].include?(pr["comment"]["user"]["login"])
          true
        else
          Sentinel.github.issues.comments.create(
            pr["repository"]["owner"]["login"],
            pr["repository"]["name"],
            pr["issue"]["number"],
            body: "Hey, @#{pr["comment"]["user"]["login"]} - you don't have permission to issue `#{command}` on this pull request.\n\n![Nope](https://cloud.githubusercontent.com/assets/4304/17754578/052ee70e-648a-11e6-9d30-c8c2b0eee26c.gif)"
          )
          false
        end
      end

      def approve_pr(pr)
        return unless authenticated?(pr, "approve")

        real_pr = Sentinel.github.pull_requests.get(
           pr["repository"]["owner"]["login"],
           pr["repository"]["name"],
           pr["issue"]["number"]
        )

        Celluloid::Actor[:processor].test(real_pr)
      end

      def force_pr(pr)
        return unless authenticated?(pr, "force")

        Sentinel.github.issues.comments.create(
          pr["repository"]["owner"]["login"],
          pr["repository"]["name"],
          pr["issue"]["number"],
          body: "Excellent @#{pr["comment"]["user"]["login"]}! It always makes me feel nice when humans approve of one anothers work, no matter the consequences. I'm merging this PR now.\n\nI just want you and the contributor to answer me one question:\n\n![gif-keyboard-3280869874741411265](https://cloud.githubusercontent.com/assets/4304/17755674/1e577b82-6490-11e6-96b7-1663d283c824.gif)"
        )

        merge(pr)
      end

      def merge_real_pr(pr)
        begin
          owner = pr["base"]["repo"]["owner"]["login"]
          repo = pr["base"]["repo"]["name"]

          approver = "Nobody from Nowhere"
          Sentinel.github.issues.comments.list(owner, repo, pr["number"]).each do |comment|
            approver = comment["user"]["login"] if comment["body"] =~ /@thesentinels approve/
          end

          Sentinel.github.pull_requests.merge(
            pr["base"]["repo"]["owner"]["login"],
            pr["base"]["repo"]["name"],
            pr["number"],
            commit_message: "Approved by: @#{approver}\nMerged by: The Sentinels"
          )

        rescue => e
          Sentinel.github.issues.comments.create(
            pr["repository"]["owner"]["login"],
            pr["repository"]["name"],
            pr["issue"]["number"],
            body: "Sorry. I had a problem merging this pull request. The error was:\n\n```ruby\n#{e}\n```\n\n![Oops](https://cloud.githubusercontent.com/assets/4304/17756537/583f4ba4-6495-11e6-97c8-0c22ceaf7e63.gif)"
          )
        end
        begin
          puts "Deleting integration branch"
          Sentinel.github.git.references.delete(
            pr["base"]["repo"]["owner"]["login"],
            pr["base"]["repo"]["name"],
            "heads/sentinel/#{owner}/#{repo}/#{pr["number"]}"
          )
          if pr["base"]["repo"]["owner"]["login"] == pr["head"]["repo"]["owner"]["login"]
            puts "Deleting local pr branch"
            Sentinel.github.git.references.delete(
              pr["base"]["repo"]["owner"]["login"],
              pr["base"]["repo"]["name"],
              "heads/#{pr["head"]["ref"]}"
            )
          else
            puts "Not deleting remote PR branch"
          end
        rescue => e
          puts "Failed to delete branches"
        end
      end

      def merge(pr)
        begin
          Sentinel.github.pull_requests.merge(
            pr["repository"]["owner"]["login"],
            pr["repository"]["name"],
            pr["issue"]["number"],
            commit_message: "Approved by: @#{pr["comment"]["user"]["login"]}\nMerged by: The Sentinels"
          )
        rescue => e
          Sentinel.github.issues.comments.create(
            pr["repository"]["owner"]["login"],
            pr["repository"]["name"],
            pr["issue"]["number"],
            body: "Sorry @#{pr["comment"]["user"]["login"]}; I had a problem merging this pull request. The error was:\n\n```ruby\n#{e}\n```\n\n![Oops](https://cloud.githubusercontent.com/assets/4304/17756537/583f4ba4-6495-11e6-97c8-0c22ceaf7e63.gif)"
          )
        end
      end
    end
  end


  class Server < Sinatra::Base
    set :bind, "0.0.0.0"

    def verify_travis(payload, signature)
      conn = Faraday.new(:url => "https://api.travis-ci.org") do |faraday|
        faraday.adapter Faraday.default_adapter
      end
      response = conn.get '/config'
      public_key = JSON.parse(response.body)["config"]["notifications"]["webhook"]["public_key"]
      pkey = OpenSSL::PKey::RSA.new(public_key)
      if pkey.verify(
          OpenSSL::Digest::SHA1.new,
          Base64.decode64(signature),
          payload.to_json
      )
        true
      else
        false
      end
    end

    post '/travis' do
      build = JSON.parse(params["payload"])
      signature = request.env["HTTP_SIGNATURE"]

      pp build if ENV["DEBUG"]
      pp signature if ENV["DEBUG"]

      if !verify_travis(build, signature)
        puts "Travis signature doesn't match - #{signature} #{build}"
        return halt 500, "Travis signature could not be verified"
      end

      if build['type'] == "pull_request"
        puts "Nothing to do on a PR travis job"
        return "Nothing to do on PR" 
      end

      build["branch"] =~ /^sentinel\/#{build["repository"]["owner_name"]}\/#{build["repository"]["name"]}\/(\d+)/
      if $1
        pr = $1
        puts "I have #{pr}"
        if build["result"] == 0
         Sentinel.github.issues.comments.create(
           build["repository"]["owner_name"],
           build["repository"]["name"],
           pr,
           body: ":sparkling_heart: Travis CI [reports this PR passed](#{build["build_url"]}).\n\nIt always makes me feel nice when humans approve of one anothers work. I'm merging this PR now.\n\nI just want you and the contributor to answer me one question:\n\n![gif-keyboard-3280869874741411265](https://cloud.githubusercontent.com/assets/4304/17755674/1e577b82-6490-11e6-96b7-1663d283c824.gif)"
         )
         real_pr = Sentinel.github.pull_requests.get(
           build["repository"]["owner_name"],
           build["repository"]["name"],
           pr
         )
         Hub.merge_real_pr(real_pr)
        elsif build["result"] == 1
          Sentinel.github.issues.comments.create(
            build["repository"]["owner_name"],
            build["repository"]["name"],
            pr,
            body: ":broken_heart: Travis CI reports [this PR failed to pass the test suite](#{build["build_url"]}).\n\nThe next step is to examine the [job](#{build["build_url"]}) and figure out why. If it is transient, you can try re-triggering the Travis CI Job - if it passes, this PR will be automatically merged. If it is not transient, you should fix the issue and update this pull request, and issue `approve` again. If you believe it will never pass, and you are feeling :godmode:, you can issue a `force` to merge this PR anyway."
          )
        elsif build["status"] == nil && build["result"] == nil && build["state"] = "started"
          Sentinel.github.issues.comments.create(
            build["repository"]["owner_name"],
            build["repository"]["name"],
            pr,
            body: ":neckbeard: Travis CI has [started testing this PR](#{build["build_url"]})."
          )
        end
      else
        puts "No PR number in #{build["branch"]}; nothing to do"
        return "No PR number in #{build["branch"]}; nothing to do"
      end

      "Please Drive Through!"
    end

    def verify_travis
    end

    post '/payload' do
      payload_body = request.body.read
      signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), SECRET_TOKEN, payload_body)
      return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
      pr = JSON.parse(payload_body)
      pp pr if ENV["DEBUG"]

      if pr["action"] == "opened" || pr["action"] == "synchronize" || pr["action"] == "reopened"
        puts "Checking #{pr["pull_request"]["head"]["repo"]["name"]} ##{pr["number"]} for DCO"
        Sentinel.github.pull_requests.commits(
          pr["repository"]["owner"]["login"],
          pr["repository"]["name"],
          pr["pull_request"]["number"]
        ).each do |commit|
          if commit[:commit][:message] !~ /Signed-off-by: .+ <.+>/
            puts "Flagging SHA #{commit["sha"]} as failed; no DCO"
            Sentinel.github.repos.statuses.create(
              pr["repository"]["owner"]["login"],
              pr["repository"]["name"],
              commit["sha"],
              context: "DCO",
              state: "failure",
              description: "This commit does not have a DCO Signed-off-by line"
            )
          else
            puts "Flagging SHA #{commit["sha"]} as succeeded; has DCO"
            Sentinel.github.repos.statuses.create(
              pr["repository"]["owner"]["login"],
              pr["repository"]["name"],
              commit["sha"],
              context: "DCO",
              state: "success",
              description: "This commit has a DCO Signed-off-by line"
            )
          end
        end
      end

      if pr.has_key?("pull_request") && pr["action"] == "opened"
        Hub.opened_pr(pr)
      elsif pr.has_key?("comment") && pr.has_key?("issue") && (pr["action"] == "created" || pr["action"] == "edited")
        if pr["comment"]["body"] =~ /@thesentinels force/
          Hub.force_pr(pr)
        elsif pr["comment"]["body"] =~ /@thesentinels approve/
          Hub.approve_pr(pr)
        end
      end

      "Please Drive Through!"
    end
  end
end

if !File.exists?("/hab/svc/sentinel/config.toml")
  puts "You need to provide a config.toml"
  exit 1
end

CONFIG = TOML.load_file("/hab/svc/sentinel/config.toml")
config = CONFIG
if !config["cfg"]["login"]
  puts "You must specify cfg.login in config.toml"
  exit 1
end

if !config["cfg"]["access_token"]
  puts "You must specify cfg.access_token in config.toml"
  exit 1
end

if config["cfg"]["secret_token"]
  SECRET_TOKEN = config["cfg"]["secret_token"]
else
  puts "You must specify cfg.secret_token in config.toml"
  exit 1
end

TOP = File.expand_path(File.join(File.dirname(__FILE__), ".."))
CACHE = "/hab/svc/sentinel/data"

Dir.mkdir(CACHE, 0700) unless Dir.exists?(CACHE)

Sentinel::Processor.supervise(:as => :processor)

