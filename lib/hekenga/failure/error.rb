module Hekenga
  class Failure
    class Error < Failure
      field :message
      field :backtrace
      field :document
      field :batch_start
    end
  end
end
