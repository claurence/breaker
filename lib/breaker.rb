require "breaker/version"
require 'timeout'

module Breaker
  CircuitOpenError = Class.new RuntimeError

  Fuse = Struct.new :name,
    :state,
    :failure_threshold,
    :retry_timeout,
    :timeout,
    :failure_count,
    :retry_threshold

  class Circuit
    attr_accessor :fuse

    def initialize(fuse, options = {})
      @fuse = fuse
    end

    def open(clock = Time.now)
      fuse.failure_count = 1
      fuse.state = :open
      fuse.retry_threshold = clock + retry_timeout
    end

    def close
      fuse.failure_count = 0
      fuse.state = :closed
      fuse.retry_threshold = nil
    end

    def open?
      fuse.state == :open
    end

    def closed?
      fuse.state == :closed
    end

    def retry_timeout
      fuse.retry_timeout
    end

    def timeout
      fuse.timeout
    end

    def run(clock = Time.now)
      if closed? || half_open?(clock)
        begin
          result = Timeout.timeout timeout do
            yield
          end

          if half_open?(clock)
            close
          end

          result
        rescue => ex
          fuse.failure_count = fuse.failure_count + 1
          fuse.retry_threshold = clock + retry_timeout

          open clock

          raise ex
        end
      else
        raise Breaker::CircuitOpenError
      end
    end

    private
    def tripped?
      fuse.failure_count != 0
    end

    def half_open?(clock)
      tripped? && clock >= fuse.retry_threshold
    end
  end
end
