# Hiero Ruby SDK

A Ruby SDK for [Hiero](https://hiero.org) — a toolkit for creating, updating, and
interacting with accounts, tokens, files, topics, and smart contracts on a Hiero network.

> **Status: pre-alpha.** The protobuf layer is in place. The client, execution engine and
> request model are not built yet, nothing is published to RubyGems, and the public API is
> not stable.

## Repository layout

One repository, two gems.

| Path | Gem | Contents |
| --- | --- | --- |
| [`proto/`](proto/) | `hiero-proto` | Protobuf message classes and gRPC service stubs for the Hiero API. Generated and committed, so installing it never requires `protoc`. |
| [`sdk/`](sdk/) | `hiero-sdk` | The SDK proper: client, execution engine, transactions, queries, keys and value types. *In progress — cryptography primitives only so far.* |

Most applications will depend on `hiero-sdk`. `hiero-proto` is the transport layer, useful
on its own only for tooling that speaks to a Hiero network directly.

## Requirements

- Ruby >= 3.2

Supported from 3.2 up to the latest release, and tested against each in CI.
Development happens on the version in [`.ruby-version`](.ruby-version); you do not
need that version to use the gem.

## Development

```sh
bundle install
bundle exec rake spec      # every suite
bundle exec rake spec:sdk  # just one
bundle exec rake build     # build the gem into pkg/
```

### Cryptography

The SDK implements Ed25519, ECDSA secp256k1 and keccak256 on Ruby's stdlib OpenSSL,
so it needs no cryptography gem to install. Signatures are byte-identical to the
other Hiero SDKs, which the specs pin against their shared test vectors.

Installing the optional `digest-keccak` gem makes hashing around 400x faster and is
picked up automatically; nothing breaks without it. The reasoning, and the
alternatives that were rejected, are in
[docs/adr/0001-cryptography-backends.md](docs/adr/0001-cryptography-backends.md).

### Working on the protobufs

The `.proto` sources are vendored into [`proto/hapi/`](proto/hapi/) from the two upstream
repositories that define them:

| Source | Provides | Pin |
| --- | --- | --- |
| [`hiero-consensus-node`](https://github.com/hiero-ledger/hiero-consensus-node) | The HAPI services, messages, streams and platform state | [`proto/HAPI_VERSION`](proto/HAPI_VERSION) |
| [`hiero-mirror-node`](https://github.com/hiero-ledger/hiero-mirror-node) | The mirror `ConsensusService`, whose `subscribeTopic` RPC backs topic subscriptions and exists nowhere else | [`proto/MIRROR_VERSION`](proto/MIRROR_VERSION) |

They are copied in rather than carried as git submodules: `hiero-consensus-node` alone is
around 570 MB, and this SDK needs about 1.4 MB of it. `--latest` follows GitHub's
`releases/latest`, which excludes drafts and pre-releases, so it never picks up an `-rc` or
`-alpha` tag.

```sh
bin/sync_protos                    # re-sync both pins as recorded
bin/sync_protos --latest           # move both pins to the latest stable release
bin/sync_protos --hapi v0.77.0     # move the consensus node pin
bin/sync_protos --mirror v0.162.0  # move the mirror node pin

bin/generate_protos                # regenerate proto/lib/hiero/proto/**
bundle exec rake protos:check      # fail if the committed output is stale
```

Both the vendored `.proto` files and the generated Ruby are committed, so a HAPI bump
arrives as a reviewable diff and installing the gem never requires `protoc`. CI regenerates
and fails on any difference, which is why `grpc-tools` is pinned in the [Gemfile](Gemfile):
a different `protoc` produces a different diff.

### Using the generated classes

```ruby
require "hiero/proto"

Hiero::Proto::VERSION        # => "0.1.0"    (this gem's version)
Hiero::Proto::HAPI_VERSION   # => "v0.76.1"  (the HAPI release these came from)
Hiero::Proto::MIRROR_VERSION # => "v0.161.3"

Proto::CryptoService::Stub                          # consensus node services
Com::Hedera::Mirror::Api::Proto::ConsensusService    # mirror node services
```

Every namespace also has its own entry file (`require "hiero/proto/services"`), though
`require "hiero/proto"` loads all of them in roughly 35 ms and there is little reason not to.

## Licence

Apache-2.0. See [LICENSE](LICENSE).

---

This repository is hosted personally while the SDK stabilises, and is intended to move to the
[hiero-ledger](https://github.com/hiero-ledger) organisation once it is ready.
