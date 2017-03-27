require 'hekenga/base_error'
module Hekenga
  class VirtualMethod < Hekenga::BaseError
    def initialize(klass, method)
      super("#{klass.to_s}##{method} has not been implemented.")
    end
  end
end
