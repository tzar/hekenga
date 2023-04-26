module Hekenga
  class Failure
    class Write < Failure
      field :message
      field :backtrace
      field :documents
      field :document_ids, type: Array
      field :batch_start
      field :task_record_id
    end
  end
end
