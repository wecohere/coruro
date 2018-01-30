require 'net/http'
require 'json'
require 'open3'

class Coruro
  # Translates between Curoro and Mailcatcher's API
  class MailcatcherAdapter
    attr_accessor :runner
    def where(to: nil, from: nil, subject: nil)
      messages.select do |message|
        match?(to, message[:recipients]) ||
        match?(from, message[:sender]) ||
        match?(subject, message[:subject])
      end.map(&method(:find_by))
    end

    def match?(query, value)
      return false if query.nil?
      return query.match?(value) if query.respond_to?(:match?) && !value.respond_to?(:any?)
      return value.any? { |child| match?(query, child) } if value.respond_to?(:any?)
      raise ArgumentError, "Query #{query} must respond to `match?` or Value #{value} must respond to `any?`"
    end

    extend Forwardable
    def_delegators :runner, :up?, :start, :stop

    def runner
      @_runner ||= Runner.instance
    end

    private def messages
      JSON.parse(Net::HTTP.get(URI("http://127.0.0.1:1080/messages")), symbolize_names: true)
    end

    private def raw_message(message_id)
      Net::HTTP.get(URI("http://127.0.0.1:1080/messages/#{message_id}.eml"))
    end


    private def find_by(attributes)
      message = Message.new(Mail.new(raw_message(attributes[:id])))
      message.id = attributes[:id]
      message
    end

    # Allows for launching and terminating mailcatcher programmaticaly
    class Runner
      include Singleton
      attr_accessor :stdin, :stdout, :stderr, :thread

      def start
        return if up?
        self.stdin, self.stdout, self.stderr, self.thread =
          Open3.popen3({ "PATH" => ENV['PATH'] }, 'mailcatcher -f', { unsetenv_others:true })
      end

      def up?
        response = Net::HTTP.get_response(URI('http://127.0.0.1:1080'))
        response.is_a?(Net::HTTPSuccess)
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL => _
        false
      end

      def stop
        self.stdin.close
        self.stdout.close
        self.stderr.close
        `kill -9 #{ thread[:pid] }`
      end
    end
  end
end
