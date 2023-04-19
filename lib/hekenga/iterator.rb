module Hekenga
  class Iterator
    include Enumerable

    SMALLEST_ID = BSON::ObjectId.from_string('0'*24)

    attr_reader :scope, :size

    def initialize(scope, size:)
      @scope = scope
      @size = size
    end

    def each(&block)
      current_id = SMALLEST_ID
      base_scope = scope.asc(:_id).limit(size)

      loop do
        ids = base_scope.gt(_id: current_id).pluck(:_id)
        break if ids.empty?
        yield ids
        current_id = ids.sort.last
      end
    end
  end
end
