require "hekenga/base_iterator"
module Hekenga
  class IdIterator < BaseIterator
    DEFAULT_ID = "_id".freeze

    attr_reader :id_property

    def initialize(id_property: DEFAULT_ID, **kwargs)
      super(**kwargs)
      @id_property = id_property
    end

    def each
      with_view do |view|
        view.each do |doc|
          yield doc[id_property]
        end
      end
    end

    private

    def with_view
      view = iteration_scope.view
      yield view
    ensure
      view.close_query
    end

    def iteration_scope
      super.only(id_property)
    end
  end
end
