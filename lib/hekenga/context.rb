module Hekenga
  class Context
    def initialize(test_mode: false)
      @__test_mode = test_mode
    end

    def actual?
      !@__test_mode
    end

    def test?
      !actual?
    end
  end
end
