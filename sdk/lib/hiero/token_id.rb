# frozen_string_literal: true

module Hiero
  # A TokenId: `shard.realm.num`, optionally carrying a ledger-scoped checksum.
  # See {EntityId} for parsing, checksums and conversions.
  class TokenId < Data.define(:shard, :realm, :num, :checksum)
    include EntityId

    def initialize(num:, shard: 0, realm: 0, checksum: nil)
      super
    end
  end
end
