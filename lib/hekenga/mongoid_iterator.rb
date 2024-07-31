require "hekenga/base_iterator"
module Hekenga
  class MongoidIterator < BaseIterator
    def each(&block)
      iteration_scope.each(&block)
    end
  end
end
