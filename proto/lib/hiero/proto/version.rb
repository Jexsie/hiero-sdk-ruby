# frozen_string_literal: true

module Hiero
  module Proto
    # This gem's own version, independent of the HAPI release it wraps. The two
    # move at different rates: a HAPI bump does not always warrant a gem release,
    # and a packaging fix should not have to claim a HAPI version it did not change.
    # Which HAPI a given gem was built from is recorded below and in the gemspec
    # metadata rather than encoded in this number.
    VERSION = "0.1.0"

    # The upstream tags the vendored .proto sources were taken from. Kept in sync
    # with proto/HAPI_VERSION and proto/MIRROR_VERSION by bin/generate_protos.
    HAPI_VERSION   = "v0.76.1"
    MIRROR_VERSION = "v0.161.3"
  end
end
