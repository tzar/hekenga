module Hekenga
  class Failure
    class Cancelled < Failure
      field :document_ids, type: Array
      field :batch_start
    end
  end
end
