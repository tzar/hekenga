require 'hekenga/base_error'
module Hekenga
  class Invalid < Hekenga::BaseError
    def initialize(instance, field, reason)
      super("#{instance.class.to_s} has #{reason} #{field}")
    end
  end
end
