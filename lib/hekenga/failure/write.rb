module Hekenga
  class Failure
    class Write < Failure
      field :message
      field :backtrace
      field :documents
      field :batch_start
    end
  end
end
