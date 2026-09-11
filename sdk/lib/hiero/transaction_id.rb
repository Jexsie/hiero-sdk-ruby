# frozen_string_literal: true

module Hiero
  # Identifies a transaction: who pays for it, and when it becomes valid.
  #
  # Written `0.0.1001@1700000000.000000000`. The network uses this for duplicate
  # detection, so two transactions sharing an id are the same transaction however
  # many times they are submitted -- which is what makes the retry loop safe to
  # run at all.
  #
  # The valid start is set slightly in the past on purpose. A node rejects a
  # transaction whose start is in its future, and clocks between a client and a
  # node differ by more than most people expect.
  class TransactionId
    include Comparable

    # How far back to place the valid start. Large enough to absorb ordinary clock
    # skew, small enough to stay well inside the network's validity window.
    CLOCK_SKEW = 5

    attr_reader :account_id, :valid_start, :scheduled, :nonce

    def initialize(account_id:, valid_start:, scheduled: false, nonce: nil)
      @account_id = AccountId.coerce(account_id)
      @valid_start = Timestamp.coerce(valid_start)
      @scheduled = scheduled
      @nonce = nonce
      freeze
    end

    class << self
      # @param account_id [AccountId, String, Integer] the account that pays
      def generate(account_id)
        now = Timestamp.now
        new(account_id: account_id,
            valid_start: Timestamp.new(seconds: now.seconds - CLOCK_SKEW, nanos: now.nanos))
      end

      # @param text [String] "shard.realm.num@seconds.nanos"
      def from_string(text)
        account, timestamp = text.to_s.strip.split("@", 2)
        raise ArgumentError, "#{text.inspect} is not a valid TransactionId" if timestamp.nil?

        seconds, nanos = timestamp.split(".", 2)
        # Base 10 explicitly. Nanoseconds are zero-padded to nine digits, and
        # Integer() reads a leading zero as octal -- ".000000123" would silently
        # become 83 nanoseconds.
        new(account_id: AccountId.from_string(account),
            valid_start: Timestamp.new(seconds: Integer(seconds, 10),
                                       nanos: nanos ? Integer(nanos, 10) : 0))
      # BadEntityIdError included: the caller asked for a TransactionId, so a bad
      # account inside one is more usefully reported as a bad TransactionId than
      # as a bad AccountId.
      rescue ArgumentError, TypeError, BadEntityIdError
        raise ArgumentError, "#{text.inspect} is not a valid TransactionId"
      end

      def from_protobuf(proto)
        new(
          account_id: AccountId.new(shard: proto.accountID.shardNum,
                                    realm: proto.accountID.realmNum,
                                    num: proto.accountID.accountNum),
          valid_start: Timestamp.new(seconds: proto.transactionValidStart.seconds,
                                     nanos: proto.transactionValidStart.nanos),
          scheduled: proto.scheduled,
          nonce: proto.nonce.zero? ? nil : proto.nonce
        )
      end
    end

    def to_protobuf
      ::Proto::TransactionID.new(
        accountID: ::Proto::AccountID.new(shardNum: @account_id.shard,
                                          realmNum: @account_id.realm,
                                          accountNum: @account_id.num),
        transactionValidStart: ::Proto::Timestamp.new(seconds: @valid_start.seconds,
                                                      nanos: @valid_start.nanos),
        scheduled: @scheduled,
        nonce: @nonce || 0
      )
    end

    # A distinct id one nanosecond later.
    #
    # Chunked transactions need several ids that sort in order, and a client
    # generating two transactions inside the same nanosecond needs them not to
    # collide -- the network would treat the second as a duplicate of the first.
    def succ
      self.class.new(account_id: @account_id, valid_start: @valid_start.succ,
                     scheduled: @scheduled, nonce: @nonce)
    end

    def to_s = "#{@account_id}@#{@valid_start}"
    def inspect = "#<#{self.class} #{self}>"

    def ==(other)
      other.is_a?(TransactionId) && other.account_id == @account_id &&
        other.valid_start == @valid_start && other.scheduled == @scheduled && other.nonce == @nonce
    end
    alias eql? ==

    def hash = [self.class, @account_id, @valid_start, @scheduled, @nonce].hash

    def <=>(other)
      return nil unless other.is_a?(TransactionId)

      [@account_id, @valid_start] <=> [other.account_id, other.valid_start]
    end
  end
end
