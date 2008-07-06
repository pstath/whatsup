require 'whatsup/urlcheck'

module Whatsup
  module Commands

    module CommandDefiner

      def all_cmds
        @@all_cmds ||= {}
      end

      def cmd(name, help, &block)
        all_cmds()[name.to_s] = help
        define_method(name, &block)
      end

    end

    class CommandProcessor

      extend CommandDefiner

      def initialize(conn)
        @jabber = conn
      end

      def dispatch(cmd, user, arg)
        if self.respond_to? cmd
          self.send cmd.to_sym, user, arg
        else
          send_msg user, "I don't understand #{cmd}.  Send `help' for what I do know."
        end
      end

      def send_msg(user, text)
        puts "Sending to #{user.jid}: #{text}"
        @jabber.deliver user.jid, text
      end

      cmd :help, "Get help for commands." do |user, arg|
        cmds = self.class.all_cmds()
        help_text = cmds.keys.sort.map {|k| "#{k}\t#{cmds[k]}"}
        send_msg user, help_text.join("\n")
      end

      cmd :get, "Get a URL" do |user, url|
        Whatsup::Urlcheck.fetch(url) do |res|
          send_msg user, "Got a #{res.status} from #{url} in #{res.time}s (#{res.body.size} bytes)"
        end
      end

      cmd :watch, "Watch a URL" do |user, url|
        Watch.create! :user => user, :url => url
      end

      cmd :on, "Activate monitoring" do |user, nothing|
        user.update_attributes(:active => true)
        send_msg user, "Marked you active."
      end

      cmd :off, "Deactivate monitoring" do |user, nothing|
        user.update_attributes(:active => false)
        send_msg user, "Marked you inactive."
      end

      cmd :watching, "List all current watches" do |user, nothing|
        watches = user.watches.map do |watch|
          "#{watch.url} (#{watch.active ? 'enabled' : 'disabled'} -- last=#{watch.status.nil? ? 'unknown' : watch.status})"
        end
        send_msg user, watches.join("\n")
      end

      cmd :enable, "Enable a watch that was specifically disabled" do |user, url|
        with_my_watch user, url do |watch|
          watch.update_attributes :active => true
          send_msg user, "Enabled watching of #{url}"
        end
      end

      cmd :disable, "Disable a watch for a specific URL" do |user, url|
        with_my_watch user, url do |watch|
          watch.update_attributes :active => false
          send_msg user, "Disabled watching of #{url}"
        end
      end

      cmd :unwatch, "Stop watching a URL" do |user, url|
        with_my_watch user, url do |watch|
          watch.destroy
          send_msg user, "Stopped watching #{url}"
        end
      end

      cmd :match, "Ensure a pattern matches for a URL" do |user, args|
        add_pattern_match user, args, true
      end

      cmd :negmatch, "Ensure a pattern does not match for a URL" do |user, args|
        add_pattern_match user, args, false
      end

      cmd :inspect, "Inspect matches for a given URL" do |user, url|
        rv=[]
        with_my_watch user, url do |watch|
          rv << "Status for #{url} (#{watch.active ? 'enabled' : 'disabled'})"
          rv << "Last status: #{watch.status} (as of #{watch.last_update.to_s})"
          if watch.patterns.empty?
            rv << "No match patterns configured"
          else
            rv << "Patterns:"
            watch.patterns.each do |p|
              rv << "\t#{p.positive ? '+' : '-'}: /#{p.regex}/"
            end
          end
        end
        send_msg user, rv.join("\n")
      end

      cmd :clear_matches, "Clear all matches for a url" do |user, url|
        with_my_watch user, url do |watch|
          watch.patterns.each {|p| p.destroy}
          send_msg user, "Removed all patterns for #{url}"
        end
      end

      private

      def add_pattern_match(user, args, positive)
        url, pattern = args.split(' ', 2)
        with_my_watch user, url do |watch|
          begin
            re = Regexp.new pattern
            watch.patterns.create :positive => positive, :regex => pattern
            send_msg user, "Configured a #{positive ? 'positive' : 'negative'} match pattern for #{url}"
          rescue RegexpError
            send_msg user, "Your regex seems broken."
          end
        end
      end

      def with_my_watch(user, url, &block)
        watch = user.watches.first(:url => url)
        if watch
          yield watch
        else
          send_msg user, "Cannot find watch for #{url}"
        end
      end

    end # CommandProcessor

  end
end