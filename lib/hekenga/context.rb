module Hekenga
  class Context
    def initialize(test_run)
      @__test_run = test_run
    end

    def test?
      !!@__test_run
    end
    def actual?
      !@__test_run
    end
  end
end
