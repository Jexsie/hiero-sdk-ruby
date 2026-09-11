# frozen_string_literal: true

module Hiero
  # Anything that can appear in a Hiero `Key` field: a public key, a key list, or
  # a threshold key. Private keys are deliberately NOT keys in this sense -- they
  # never travel to the network and are not part of the protobuf Key structure.
  class Key
    # Conversion to the protobuf Key structure arrives with the transaction layer.
    # Keeping it out for now means the key and value types stay loadable without
    # pulling in gRPC, which is what makes them useful to wallets and address
    # tooling that never talk to a consensus node.
    def to_protobuf_key
      raise NotImplementedError, "#{self.class} does not implement to_protobuf_key"
    end

    # Reads any protobuf Key back into whichever type it represents.
    #
    # @return [PublicKey, KeyList, nil]
    def self.from_protobuf_key(key)
      return nil if key.nil?

      case key.key
      when :ed25519, :ECDSA_secp256k1 then PublicKey.from_protobuf_key(key)
      when :keyList then KeyList.new(key.keyList.keys.map { |member| from_protobuf_key(member) })
      when :thresholdKey
        KeyList.new(key.thresholdKey.keys.keys.map { |member| from_protobuf_key(member) },
                    threshold: key.thresholdKey.threshold)
      end
    end
  end
end
