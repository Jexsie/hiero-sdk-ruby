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

  # A derivation index produced an invalid key. Specified by BIP-32 and vanishingly
  # rare; the remedy is to use the next index.
  class KeyDerivationError < Error; end
end
