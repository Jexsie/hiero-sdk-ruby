# frozen_string_literal: true

module Hiero
  # A TopicId: `shard.realm.num`, optionally carrying a ledger-scoped checksum.
  # See {EntityId} for parsing, checksums and conversions.
  class TopicId < Data.define(:shard, :realm, :num, :checksum)
    include EntityId

    def initialize(num:, shard: 0, realm: 0, checksum: nil)
      super
    end
  end
end
