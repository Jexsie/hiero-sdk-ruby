# frozen_string_literal: true

module Hiero
  # A BIP-39 mnemonic phrase.
  #
  # Construction validates: the word count, that every word is in the BIP-39
  # English list, and the checksum. An instance is therefore always a phrase that
  # can actually produce a key, which is what makes it safe to accept one anywhere
  # in the API.
  #
  # Recovering a key needs both the phrase and the derivation path, and the two
  # standard paths differ per algorithm:
  #
  #   Ed25519          m/44'/3030'/0'/0'/index'   every level hardened
  #   ECDSA secp256k1  m/44'/3030'/0'/0/index     the last two unhardened
  #
  # Using the wrong one yields a perfectly valid key for a different account, with
  # nothing to indicate the mistake, so prefer the to_standard_* methods over
  # assembling a path by hand.
  class Mnemonic
    COIN_TYPE = 3030 # Hedera's SLIP-44 registration, retained by Hiero.
    PURPOSE   = 44

    include Enumerable

    attr_reader :words

    # @param words [Array<String>]
    def initialize(words)
      @words = words.map { |word| word.to_s.strip.downcase }.freeze
      Crypto::Bip39.words_to_entropy(@words) # validates length, vocabulary and checksum
      freeze
    end

    class << self
      # @param length [Integer] 12, 15, 18, 21 or 24
      def generate(length = 24)
        unless Crypto::Bip39::VALID_LENGTHS.include?(length)
          raise ArgumentError, "expected #{Crypto::Bip39::VALID_LENGTHS.join(', ')} words, got #{length}"
        end

        # 11 bits per word, of which one in 33 is checksum.
        entropy_bytes = length * 11 / 33 * 4
        from_entropy(OpenSSL::Random.random_bytes(entropy_bytes))
      end

      def generate_12 = generate(12)
      def generate_24 = generate(24)

      def from_entropy(entropy) = new(Crypto::Bip39.entropy_to_words(entropy))

      def from_words(words) = new(Array(words))

      # Accepts words separated by whitespace or commas. Phrases get copied out of
      # wallets and spreadsheets in both forms.
      def from_string(text) = new(text.to_s.strip.split(/[\s,]+/))
    end

    def each(&) = @words.each(&)
    def length = @words.length
    alias size length

    def to_entropy = Crypto::Bip39.words_to_entropy(@words)

    # @param passphrase [String] the optional BIP-39 passphrase. Not the mnemonic,
    #   and not a password on this object -- a different passphrase silently yields
    #   a different, equally valid set of keys.
    # @return [String] the 64-byte seed
    def to_seed(passphrase = "") = Crypto::Bip39.to_seed(@words, passphrase)

    # The Ed25519 key at m/44'/3030'/0'/0'/index'.
    def to_standard_ed25519_private_key(passphrase = "", index = 0)
      PrivateKey.from_seed_ed25519(to_seed(passphrase))
                .derive_path(PURPOSE, COIN_TYPE, 0, 0, index)
    end

    # The ECDSA secp256k1 key at m/44'/3030'/0'/0/index.
    def to_standard_ecdsa_private_key(passphrase = "", index = 0)
      harden = Crypto::Bip32.method(:harden)
      PrivateKey.from_seed_ecdsa(to_seed(passphrase))
                .derive_path(harden.(PURPOSE), harden.(COIN_TYPE), harden.(0), 0, index)
    end

    def ==(other) = other.is_a?(Mnemonic) && other.words == @words
    alias eql? ==

    def hash = [self.class, @words].hash

    def to_s = @words.join(" ")

    # A mnemonic is a private key in another form, so it is redacted for the same
    # reasons {PrivateKey} is -- see the note there.
    def inspect = "#<#{self.class} #{length} words [redacted]>"
  end
end
