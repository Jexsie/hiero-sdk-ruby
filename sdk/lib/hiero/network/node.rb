# frozen_string_literal: true

module Hiero
  module Network
    # One node in a network, and its health.
    #
    # A node that fails is not dropped: it is put aside for a growing interval and
    # tried again later. The interval doubles with each consecutive failure from
    # {MIN_BACKOFF} up to {MAX_BACKOFF}, and any success halves it back down. This
    # keeps a briefly unreachable node from being hammered while still letting it
    # return to service on its own.
    #
    # Readmission is lazy -- there is no timer. A node rejoins the healthy pool
    # the next time the network is asked for one, which is the only moment the
    # answer matters.
    class Node
      MIN_BACKOFF = 8.0
      MAX_BACKOFF = 3600.0

      attr_reader :address, :account_id, :use_count, :bad_status_count, :backoff, :readmit_at

      # @param address [String] "host:port"
      # @param account_id [AccountId] the account this node is paid through
      def initialize(address:, account_id:, min_backoff: MIN_BACKOFF, max_backoff: MAX_BACKOFF)
        @address = address
        @account_id = AccountId.coerce(account_id)
        @min_backoff = min_backoff
        @max_backoff = max_backoff

        @backoff = min_backoff
        @readmit_at = nil
        @bad_status_count = 0
        @use_count = 0
        @mutex = Monitor.new
      end

      # @return [Boolean] whether this node may be used now
      def healthy?(now = Clock.now)
        @mutex.synchronize { @readmit_at.nil? || now >= @readmit_at }
      end

      # Records a failure: double the backoff and stand the node down for that long.
      def increase_backoff!(now = Clock.now)
        @mutex.synchronize do
          @readmit_at = now + @backoff
          @backoff = [@backoff * 2, @max_backoff].min
          @bad_status_count += 1
          self
        end
      end

      # Records a success: readmit immediately and halve the backoff.
      #
      # Halving rather than resetting is deliberate. A node flapping between
      # working and failing should not have its penalty wiped by every success, or
      # the backoff would never grow past the first step.
      def decrease_backoff!
        @mutex.synchronize do
          @readmit_at = nil
          @backoff = [@backoff / 2, @min_backoff].max
          self
        end
      end

      def record_use! = @mutex.synchronize { @use_count += 1 }

      # @param max_attempts [Integer] -1 to never evict, which is the default
      #   everywhere -- a node is far more often briefly unreachable than actually
      #   gone, and evicting it permanently is not recoverable without a restart.
      def dead?(max_attempts)
        return false if max_attempts.negative?

        @mutex.synchronize { @bad_status_count >= max_attempts }
      end

      def to_s = "#{@account_id}@#{@address}"
      def inspect = "#<#{self.class} #{self} healthy=#{healthy?} backoff=#{@backoff}s>"
    end
  end
end
