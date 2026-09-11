# frozen_string_literal: true

module Hiero
  # Base class for everything this SDK raises. `rescue Hiero::Error` catches the
  # SDK and nothing else.
  class Error < StandardError; end

  # A key could not be parsed, is the wrong length, is not a valid point on the
  # curve, or was asked to do something its algorithm does not support.
  class BadKeyError < Error; end

  # A mnemonic phrase is the wrong length, contains words outside the BIP-39 list,
  # or fails its checksum.
  #
  # #reason distinguishes the three, because they call for different responses: a
  # length problem means words were lost, unknown words are usually a typo worth
  # showing back to the user, and a checksum failure means the words are all real
  # but at least one is wrong or out of order.
  class BadMnemonicError < Error
    attr_reader :reason, :unknown_words

    def initialize(message, reason:, unknown_words: [])
      super(message)
      @reason = reason
      @unknown_words = unknown_words
    end
  end

  # An entity identifier could not be parsed, or carries a checksum that does not
  # match the network it was used against -- usually a mainnet identifier pasted
  # into a testnet application, or the reverse.
  class BadEntityIdError < Error; end

  # Every attempt was used, or the overall time budget ran out.
  #
  # #cause carries the last underlying failure, so Ruby's own exception chaining
  # shows why the retries failed rather than burying it in a message string.
  class MaxAttemptsError < Error
    attr_reader :attempts, :node_account_id

    def initialize(message, attempts:, node_account_id:, cause: nil)
      super(message)
      @attempts = attempts
      @node_account_id = node_account_id
      @underlying = cause
    end

    class << self
      def exhausted(attempts, cause, node_account_id)
        new("exhausted #{attempts} attempts#{because(cause)}",
            attempts: attempts, node_account_id: node_account_id, cause: cause)
      end

      def timeout(attempts, budget, cause, node_account_id)
        new("timed out after #{budget}s and #{attempts} attempts#{because(cause)}",
            attempts: attempts, node_account_id: node_account_id, cause: cause)
      end

      def because(cause) = cause ? "; last failure: #{cause.message}" : ""
    end

    # Ruby only sets #cause automatically when raising from inside a rescue, and
    # the last failure here was rescued several attempts ago.
    def cause = @underlying || super
  end

  # A node refused the request before consensus -- a bad signature, an unknown
  # entity, an insufficient balance. Nothing reached consensus and no fee was
  # charged, which is what distinguishes this from a failure after consensus.
  class PrecheckStatusError < Error
    attr_reader :status, :node_account_id, :transaction_id

    def initialize(status:, node_account_id:, transaction_id: nil)
      @status = status
      @node_account_id = node_account_id
      @transaction_id = transaction_id
      super("node #{node_account_id} rejected the request: #{status}")
    end
  end

  # A frozen transaction was modified. Its signatures cover the current body, so
  # changing it would invalidate every signature already collected.
  class TransactionFrozenError < Error; end

  # A transaction reached consensus and failed there.
  #
  # Distinct from PrecheckStatusError because the consequences differ: this one
  # was charged for. Code that retries on failure needs to know which it got, or
  # it pays twice.
  class ReceiptStatusError < Error
    attr_reader :status, :transaction_id

    def initialize(status:, transaction_id: nil)
      @status = status
      @transaction_id = transaction_id
      super("transaction #{transaction_id} reached consensus and failed: #{status}")
    end
  end

  # A query would cost more than the caller agreed to pay.
  #
  # Raised before anything is spent -- the price is discovered first, and the
  # payment is only signed once it is under the ceiling.
  class MaxQueryPaymentExceededError < Error
    attr_reader :cost, :maximum, :query

    def initialize(cost:, maximum:, query: nil)
      @cost = cost
      @maximum = maximum
      @query = query
      super("#{query || 'this query'} costs #{cost}, which is more than the #{maximum} limit. " \
            "Raise max_query_payment, or set query_payment to pay a fixed amount.")
    end
  end

  # A Client was used after being closed.
  class ClientClosedError < Error; end

  # A derivation index produced an invalid key. Specified by BIP-32 and vanishingly
  # rare; the remedy is to use the next index.
  class KeyDerivationError < Error; end
end
