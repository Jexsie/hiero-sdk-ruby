# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "hiero"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

# Test vectors taken from the JavaScript SDK's cryptography suite
# (packages/cryptography/test/unit). They are shared across the Hiero SDKs, so
# agreeing with them is what "compatible" actually means here -- an SDK that
# signs self-consistently but differently from its siblings is broken.
module Vectors
  ED25519_SEED = "db484b828e64b2d8f12ce3c0a0e93a0b8cce7af1bb8f39c97732394482538e10"
  ED25519_PUBLIC = "e0c8ec2758a5879ffac226a13c0c516b799e72e35141a0dd828f94d37988a4b7"
  ED25519_PRIVATE_DER =
    "302e020100300506032b657004220420db484b828e64b2d8f12ce3c0a0e93a0b8cce7af1bb8f39c97732394482538e10"

  ECDSA_PRIVATE = "8776c6b831a1b61ac10dac0304a2843de4716f54b1919bb91a2685d0fe3f3048"

  # sign(keccak256("hello world"))
  ECDSA_MESSAGE = "hello world"
  ECDSA_SIGNATURE =
    "f3a13a555f1f8cd6532716b8f388bd4e9d8ed0b252743e923114c0c6cbfe414c" \
    "086e3717a6502c3edff6130d34df252fb94b6f662d0cd27e2110903320563851"

  # sign(keccak256(<a real serialized transaction body>))
  ECDSA_BODY_BYTES =
    "0a0e0a0408011001120608001000180412060800100018031880c2d72f2202087832007" \
    "21a0a180a0a0a0608001000180410130a0a0a060800100018051014"
  ECDSA_BODY_SIGNATURE =
    "63201532040178a60e2738bdaaa00d628004b15d109162fa42e066fcb6720190" \
    "438473bbf155fd7ff6bfb2a94141157f1e1a080aa84473d7f4c68f8025275a0a"

  # The canonical empty-input Keccak digest. Distinguishes Keccak from SHA3-256,
  # which pads differently and returns something else entirely.
  KECCAK_EMPTY = "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"

  def self.bin(hex) = [hex].pack("H*")
end
