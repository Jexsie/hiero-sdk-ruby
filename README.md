# Hiero Ruby SDK

A Ruby SDK for [Hiero](https://hiero.org) — a toolkit for creating, updating, and
interacting with accounts, tokens, files, topics, and smart contracts on a Hiero network.

> **Status: pre-alpha.** The protobuf layer is in place; the client, execution engine and
> request model are still being built. Nothing here is published to RubyGems yet, and the
> public API is not stable.

## Repository layout

This is a single repository publishing two gems.

| Path | Gem | Contents |
| --- | --- | --- |
| [`proto/`](proto/) | `hiero-proto` | Generated protobuf message and gRPC service classes for the Hiero API (HAPI). Machine-generated and committed — installing it never requires `protoc`. Versioned to the HAPI release it was generated from. |
| `sdk/` | `hiero-sdk` | The SDK proper: client, execution engine, transactions, queries, keys and value types. *Not yet started.* |

## Requirements

- Ruby >= 3.2

## Working on the protobufs

The HAPI `.proto` sources are vendored into [`proto/hapi/`](proto/hapi/) from
[`hiero-ledger/hiero-consensus-node`](https://github.com/hiero-ledger/hiero-consensus-node)
at the tag recorded in [`proto/HAPI_VERSION`](proto/HAPI_VERSION). They are copied in rather
than pulled as a git submodule: the consensus node repository is roughly 570 MB, and this
SDK needs a few hundred kilobytes of it.

```sh
bin/sync_protos              # fetch the pinned HAPI tag into proto/hapi/
bin/sync_protos v0.77.0      # ...or move the pin to a different tag
bin/generate_protos          # regenerate proto/lib/hiero/proto/** from proto/hapi/
```

Both the vendored `.proto` files and the generated Ruby are committed, so a regeneration
shows up as a reviewable diff.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
