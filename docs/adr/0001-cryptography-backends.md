# 1. Cryptography backends

- **Status:** accepted
- **Date:** 2026-08-27

## Context

Hiero needs three cryptographic primitives:

| Primitive | Used for |
| --- | --- |
| Ed25519 | The default key type. Signing transactions. |
| ECDSA secp256k1 | The other key type. Signing transactions, and EVM compatibility. |
| keccak256 | Hashing the message ECDSA signs, and deriving EVM addresses. |

Ruby offers several ways to get each, and they are not interchangeable. Two
requirements make the choice unusually constrained:

**Signatures must match the other SDKs byte for byte.** Hiero signs
`keccak256(message)` with a deterministic nonce (RFC 6979) and `s` normalised into
the lower half of the curve order. A signature that verifies but differs from what
the Java, JavaScript and Go SDKs produce fails the shared conformance vectors, and
a high-`s` signature is rejected outright by the EVM.

**Getting it wrong is silent.** keccak256 and SHA3-256 differ only in a padding
byte. Substituting one for the other returns a plausible digest and produces wrong
EVM addresses everywhere, with nothing to indicate a problem.

A dependency also has a cost that is easy to underestimate for a Ruby gem: a native
extension has to build on every machine and in every CI image and container that
installs the SDK.

## Decision

**Use Ruby's stdlib OpenSSL for Ed25519 and secp256k1, and a pure-Ruby keccak256,
with the optional `digest-keccak` gem used automatically when present.**

`hiero-sdk` therefore has no cryptography dependency at all.

### Ed25519 — stdlib OpenSSL, via DER

Hiero keys are raw 32-byte seeds and OpenSSL's PKey API is built around DER, which
is the usual reason to reach for a native gem. It is not an obstacle: the DER
encodings are a fixed prefix followed by the key bytes, so converting is a
concatenation.

Everything goes through `OpenSSL::PKey.read` rather than the more direct
`new_raw_private_key` / `raw_public_key`, because those arrived in the openssl gem
3.2 and Ruby 3.2 — the supported floor — ships 3.1.2. The underlying libssl handles
Ed25519 in both cases; only the Ruby binding differs. This was found by running the
suite on the floor rather than by reading release notes, and is why CI tests 3.2.

### secp256k1 — stdlib OpenSSL, with the nonce derived here

OpenSSL provides the curve arithmetic but chooses a random nonce, so its signatures
differ on every run and can never reproduce the shared vectors. The nonce is
therefore derived per RFC 6979 (HMAC-SHA256 over the private key and digest) and the
final scalar arithmetic done directly, with explicit low-`s` normalisation.

Verified byte-identical to libsecp256k1 on both cross-SDK vectors, at roughly
0.17 ms per signature.

Determinism is not only about matching vectors. A repeated or predictable nonce
leaks the private key outright, so deriving it from the key and message removes a
whole class of failure that a random source can introduce.

### keccak256 — pure Ruby, native if available

A pure-Ruby Keccak-256 is about 60 lines and agrees with the native implementation
on every input tested, including the padding edge cases either side of the 136-byte
rate. It is 413 µs per hash against 1 µs for `digest-keccak` — 413x slower, but
keccak is called once per signature and once per address derivation, not in a loop.

`digest-keccak` is detected at load and used when installed, so anyone who needs the
throughput gets it by adding one gem, and nobody is forced to build a native
extension to use the SDK.

## Alternatives considered

**`rbsecp256k1`** — the obvious choice, and it does reproduce the vectors exactly.
Rejected on install burden: version 6.0.0 vendors libsecp256k1 0.2.0 and builds it
with autotools, so installing it needs `autoconf` and `automake` present.
`--with-system-libraries` did not avoid this. Requiring build tooling to install a
Ruby SDK is a poor trade for arithmetic that stdlib already performs correctly.

**The `ed25519` gem** — works, and derives the right public key from a raw seed.
Rejected only because stdlib does the same thing with nothing to install.

**OpenSSL's own ECDSA signing (`dsa_sign_asn1`)** — produces valid signatures, but
non-deterministically. Confirmed by signing the same digest twice and getting
different results. Cannot satisfy the conformance vectors.

**SHA3-256 for keccak** — not viable, and worth naming explicitly because it is the
most likely mistake here. There is a spec asserting the two differ.

## Consequences

- No cryptography gem is required to install or use `hiero-sdk`.
- We own an RFC 6979 implementation and a Keccak sponge. Both are pinned by the
  cross-SDK vectors, which is what makes that ownership acceptable — the vectors
  fail loudly if either drifts.
- The secp256k1 path is not constant-time in the way libsecp256k1 is. The scalar
  multiplication is OpenSSL's, and the deterministic nonce removes the RNG as a
  factor, but a side-channel-hardened backend would still be preferable for a
  signing service handling untrusted load. If that becomes a requirement, the
  module boundary is narrow enough to swap.
- CI installs `digest-keccak` so the native path is exercised too, while the
  default pure-Ruby path is what the floor build runs.
