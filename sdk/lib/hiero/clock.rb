# frozen_string_literal: true

module Hiero
  # The clock the SDK measures elapsed time with.
  #
  # Deliberately monotonic. Retry deadlines and node backoff are durations, not
  # points in time, and the wall clock can move backwards -- an NTP correction, a
  # leap second, a laptop waking from sleep. Measuring a timeout against
  # Time.now can make a retry loop hang or spin depending on which way the
  # correction went, and the failure is rare enough to be very hard to diagnose.
  #
  # {Timestamp} is the opposite case and correctly uses wall time: a consensus
  # timestamp names a moment, and has to agree with the rest of the world.
  module Clock
    module_function

    # @return [Float] seconds from an arbitrary origin, never decreasing
    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
