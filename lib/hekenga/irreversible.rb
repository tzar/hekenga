require 'hekenga/base_error'
module Hekenga
  class Irreversible < Hekenga::BaseError
    def initialize(task)
      super("#{task.inspect} is not a reversible.")
    end
  end
end
