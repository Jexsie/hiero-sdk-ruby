# frozen_string_literal: true

require "openssl"

module Hiero
  module Crypto
    # BIP-39: turning entropy into a word list and back, and stretching a word
    # list into a 64-byte seed.
    module Bip39
      # Each word encodes 11 bits, and a mnemonic is entropy plus a checksum of
      # one bit per three words.
      BITS_PER_WORD = 11
      VALID_LENGTHS = [12, 15, 18, 21, 24].freeze

      # PBKDF2 parameters are fixed by the specification; they are not tuning knobs.
      PBKDF2_ITERATIONS = 2048
      SEED_LENGTH = 64

      WORDLIST_PATH = File.join(__dir__, "wordlists", "english.txt")

      # The canonical BIP-39 English list, verified against its published SHA-256
      # in the specs. A single altered word would produce valid-looking mnemonics
      # that decode to the wrong entropy everywhere else.
      WORDLIST = File.readlines(WORDLIST_PATH, chomp: true).map(&:freeze).freeze

      # Word to index, so validation is a hash lookup rather than a linear scan.
      WORD_INDEX = WORDLIST.each_with_index.to_h.freeze

      module_function

      # @param words [Array<String>]
      # @param passphrase [String] the optional BIP-39 passphrase, not the mnemonic
      # @return [String] a 64-byte seed
      def to_seed(words, passphrase = "")
        OpenSSL::KDF.pbkdf2_hmac(
          words.join(" ").unicode_normalize(:nfkd),
          salt: "mnemonic#{passphrase}".unicode_normalize(:nfkd),
          iterations: PBKDF2_ITERATIONS,
          length: SEED_LENGTH,
          hash: "SHA512"
        )
      end

      # @param entropy [String] 16 to 32 bytes, a multiple of 4
      # @return [Array<String>] the mnemonic words
      def entropy_to_words(entropy)
        entropy = entropy.b
        unless (16..32).cover?(entropy.bytesize) && (entropy.bytesize % 4).zero?
          raise ArgumentError, "entropy must be 16-32 bytes and a multiple of 4, got #{entropy.bytesize}"
        end

        checksum_bits = entropy.bytesize * 8 / 32
        bits = to_bit_string(entropy) + to_bit_string(OpenSSL::Digest.digest("SHA256", entropy))[0, checksum_bits]

        bits.scan(/.{#{BITS_PER_WORD}}/).map { |chunk| WORDLIST[chunk.to_i(2)] }
      end

      # @param words [Array<String>]
      # @return [String] the entropy the words encode
      # @raise [BadMnemonicError] if the length, vocabulary or checksum is wrong
      def words_to_entropy(words)
        validate_length!(words)
        indices = words.map { |word| WORD_INDEX.fetch(word) { raise_unknown_word(words, word) } }

        bits = indices.map { |i| i.to_s(2).rjust(BITS_PER_WORD, "0") }.join
        checksum_bits = bits.length / 33
        entropy_bits = bits.length - checksum_bits

        entropy = [bits[0, entropy_bits]].pack("B*")
        expected = to_bit_string(OpenSSL::Digest.digest("SHA256", entropy))[0, checksum_bits]

        unless bits[entropy_bits, checksum_bits] == expected
          raise BadMnemonicError.new("mnemonic checksum does not match", reason: :checksum)
        end

        entropy
      end

      def valid_word?(word) = WORD_INDEX.key?(word)

      def validate_length!(words)
        return if VALID_LENGTHS.include?(words.length)

        raise BadMnemonicError.new(
          "expected #{VALID_LENGTHS.join(', ')} words, got #{words.length}",
          reason: :length
        )
      end

      def raise_unknown_word(words, word)
        raise BadMnemonicError.new(
          "#{word.inspect} is not in the BIP-39 English word list",
          reason: :unknown_word,
          unknown_words: words.reject { |w| WORD_INDEX.key?(w) }
        )
      end

      def to_bit_string(bytes) = bytes.b.unpack1("B*")
    end
  end
end
