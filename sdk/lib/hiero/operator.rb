# frozen_string_literal: true

module Hiero
  # The account that pays, and the means of signing on its behalf.
  #
  # The signer is a callable taking bytes and returning a signature, so the
  # private key need not be in the process at all -- an HSM or KMS satisfies this
  # contract as readily as a local key, which matters for server deployments where
  # holding key material in application memory is not acceptable.
  class Operator
    attr_reader :account_id, :public_key

    # @param account_id [AccountId, String, Integer]
    # @param private_key [PrivateKey, nil] convenience for the local-key case
    # @param public_key [PublicKey, nil] required when signing remotely
    # @yieldparam bytes [String] the bytes to sign
    # @yieldreturn [String] the signature
    def initialize(account_id:, private_key: nil, public_key: nil, &signer)
      @account_id = AccountId.coerce(account_id)

      if private_key
        raise ArgumentError, "give a private_key or a signer block, not both" if signer

        @public_key = private_key.public_key
        @signer = private_key.method(:sign)
      else
        raise ArgumentError, "an Operator needs a private_key or a public_key and a signer" unless public_key && signer

        @public_key = public_key
        @signer = signer
      end

      freeze
    end

    # @param bytes [String]
    # @return [String] the signature
    def sign(bytes) = @signer.call(bytes)

    # Redacted for the same reason {PrivateKey} is: this holds, or can reach, key
    # material, and Ruby prints objects far more eagerly than is safe for that.
    def to_s = inspect
    def inspect = "#<#{self.class} #{@account_id} key=#{@public_key.to_string_raw[0, 16]}...>"
  end
end
