module Hekenga
  class Failure
    class Validation < Failure
      field :doc_id, type: BSON::ObjectId
      field :errs
      field :document
    end
  end
end
