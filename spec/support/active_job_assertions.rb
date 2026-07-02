# ActiveJob's test helpers (e.g. perform_enqueued_jobs) wrap the yielded block
# in ActiveSupport::Testing::Assertions#assert_nothing_raised. That method is
# written for a Minitest runtime: it calls `assert(true)` on success and wraps
# any error in Minitest::UnexpectedError. Under RSpec neither `assert` nor the
# Minitest constant exist, so the helper blows up (masking the real error).
#
# Rather than loading Minitest just to satisfy those references, we override
# the single offending method to run the block and let genuine errors surface
# naturally. Requiring the helper first guarantees the original definition is
# in place before we reopen the module.
require "active_job/test_helper"

module ActiveSupport
  module Testing
    module Assertions
      def assert_nothing_raised
        yield
      end
    end
  end
end
