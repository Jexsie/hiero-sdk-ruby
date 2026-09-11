# frozen_string_literal: true

module Hiero
  # Shared behaviour for the `shard.realm.num` entity identifiers: AccountId,
  # ContractId, FileId, TokenId, TopicId and ScheduleId.
  #
  # Included rather than inherited, because each identifier is its own
  # {Data} class -- they carry different extra fields, and a TokenId must never
  # compare equal to a TopicId with the same numbers.
  #
  # == Checksums
  #
  # An identifier may carry a five-letter checksum: `0.0.123-vfmkw`. It is derived
  # from the numbers *and the ledger*, so the same entity checksums differently on
  # each network:
  #
  #   0.0.123 on mainnet     -> 0.0.123-vfmkw
  #   0.0.123 on testnet     -> 0.0.123-esxsf
  #   0.0.123 on previewnet  -> 0.0.123-ogizo
  #
  # That is the whole point of them. Pasting a mainnet address into a testnet
  # application is an easy and expensive mistake, and the checksum turns it from a
  # transfer to the wrong entity into a loud failure.
  #
  # Checksums are not verified unless asked for, matching the other SDKs: an
  # identifier parsed with one keeps it, and {#validate_checksum!} compares it.
  module EntityId
    # Base 26, five letters. The constants below follow the reference
    # implementation exactly; they are not independently meaningful.
    P3 = 26**3
    P5 = 26**5
    ASCII_A = "a".ord
    PRIME = 1_000_003 # smallest prime above a million, for the final permutation
    WEIGHT = 31       # digit weighting, coprime to P5

    # shard.realm.num, each a non-negative integer, with an optional checksum.
    PATTERN = /\A(\d+)\.(\d+)\.(\d+)(?:-([a-z]{5}))?\z/

    module ClassMethods
      # @param text [String] "0.0.123", "0.0.123-vfmkw", or a bare "123"
      def from_string(text)
        text = text.to_s.strip
        match = PATTERN.match(text) || /\A(\d+)\z/.match(text)
        raise BadEntityIdError, "#{text.inspect} is not a valid #{name}" unless match

        if match.captures.length == 1
          new(num: Integer(match[1]))
        else
          new(shard: Integer(match[1]), realm: Integer(match[2]),
              num: Integer(match[3]), checksum: match[4])
        end
      end

      # The 20-byte "long-zero" EVM form: 4 bytes of shard, 8 of realm, 8 of num.
      def from_solidity_address(address)
        bytes = Encoding.decode_hex(address)
        unless bytes.bytesize == 20
          raise BadEntityIdError, "a solidity address is 20 bytes, got #{bytes.bytesize}"
        end

        new(shard: bytes[0, 4].unpack1("H*").to_i(16),
            realm: bytes[4, 8].unpack1("H*").to_i(16),
            num: bytes[12, 8].unpack1("H*").to_i(16))
      end

      # Accepts whatever a caller is likely to have: the identifier itself, a
      # string, a bare entity number, or an object that knows how to become one.
      #
      # This is what keeps application code free of
      # `Hiero::AccountId.from_string(...)` noise at every call site.
      def coerce(value)
        converter = :"to_#{name.split('::').last.gsub(/(.)([A-Z])/, '\1_\2').downcase}"

        case value
        when self then value
        when String then from_string(value)
        when Integer then new(num: value)
        when nil then nil
        else
          return value.public_send(converter) if value.respond_to?(converter)

          raise BadEntityIdError, "cannot interpret #{value.inspect} as a #{name}"
        end
      end
    end

    def self.included(base) = base.extend(ClassMethods)

    # @return [String] "shard.realm.num", without a checksum
    def to_s = "#{shard}.#{realm}.#{num}"

    def inspect = "#<#{self.class} #{self}>"

    # @param ledger [LedgerId, Symbol, String] the network to scope the checksum to
    # @return [String] "shard.realm.num-checksum"
    def to_string_with_checksum(ledger)
      "#{self}-#{checksum_for(ledger)}"
    end

    # @return [String] the five-letter checksum for this identifier on `ledger`
    def checksum_for(ledger)
      ledger = LedgerId.coerce(ledger)
      raise ArgumentError, "a ledger is required to compute a checksum" if ledger.nil?

      address = to_s
      digits = address.chars.map { |char| char == "." ? 10 : char.to_i }

      weighted = 0
      even_sum = 0
      odd_sum = 0
      digits.each_with_index do |digit, index|
        weighted = (WEIGHT * weighted + digit) % P3
        if index.even?
          even_sum = (even_sum + digit) % 11
        else
          odd_sum = (odd_sum + digit) % 11
        end
      end

      ledger_hash = 0
      # Six zero bytes are appended to the ledger id before hashing; this is part
      # of the specified algorithm, not padding we are free to change.
      (ledger.to_bytes.bytes + [0] * 6).each do |byte|
        ledger_hash = (WEIGHT * ledger_hash + byte) % P5
      end

      value = ((((address.length % 5) * 11 + even_sum) * 11 + odd_sum) * P3 + weighted + ledger_hash) % P5
      value = (value * PRIME) % P5

      Array.new(5) do
        letter = (ASCII_A + (value % 26)).chr
        value /= 26
        letter
      end.reverse.join
    end

    # @raise [BadEntityIdError] if this identifier carries a checksum that does not
    #   match the one `ledger` implies
    def validate_checksum!(ledger)
      return self if checksum.nil?

      expected = checksum_for(ledger)
      return self if checksum == expected

      raise BadEntityIdError,
            "#{self}-#{checksum} has the wrong checksum for #{LedgerId.coerce(ledger)}; " \
            "expected #{self}-#{expected}. Is this identifier from a different network?"
    end

    def valid_checksum?(ledger)
      validate_checksum!(ledger)
      true
    rescue BadEntityIdError
      false
    end

    # @return [String] the 20-byte long-zero EVM address, as hex
    def to_solidity_address
      Encoding.encode_hex([shard].pack("N") + [realm].pack("Q>") + [num].pack("Q>"))
    end

    # Two identifiers of the same type addressing the same entity are equal, with
    # or without a checksum -- the checksum is a property of how the identifier was
    # written down, not of what it points at.
    def ==(other)
      other.instance_of?(self.class) &&
        other.shard == shard && other.realm == realm && other.num == num
    end
    alias eql? ==

    def hash = [self.class, shard, realm, num].hash

    include Comparable

    def <=>(other)
      return nil unless other.instance_of?(self.class)

      [shard, realm, num] <=> [other.shard, other.realm, other.num]
    end
  end
end
