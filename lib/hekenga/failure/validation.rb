module Hekenga
  class Failure
    class Validation < Failure
      field :doc_id, type: BSON::ObjectId
      field :errors
      field :document
    end
  end
end
