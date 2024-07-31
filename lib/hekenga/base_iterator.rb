module Hekenga
  class BaseIterator
    include Enumerable
    DEFAULT_TIMEOUT = 86_400 # 1 day in seconds

    attr_reader :cursor_timeout

    def initialize(scope:, cursor_timeout: DEFAULT_TIMEOUT)
      @scope = scope
      @cursor_timeout = cursor_timeout
    end

    private

    def iteration_scope
      if @scope.selector.blank? && @scope.options.blank?
        # Apply a default _id sort, it works the best
        @scope.asc(:_id)
      else
        @scope
      end.max_time_ms(cursor_timeout * 1000) # convert to ms
    end
  end
end
