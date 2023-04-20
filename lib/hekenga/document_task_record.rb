module Hekenga
  class DocumentTaskRecord
    include Mongoid::Document

    field :migration_key, type: String
    field :task_idx, type: Integer
    field :executor_key, type: BSON::ObjectId
    field :finished, type: Time
    field :complete, type: Boolean, default: false
    field :ids, type: Array, default: []
    field :id_count, type: Integer
    field :test_mode, type: Boolean

    field :stats,       type: Hash,  default: {}
    field :failed_ids,  type: Array, default: []
    field :invalid_ids, type: Array, default: []
    field :written_ids, type: Array, default: []

    index(migration_key: 1, task_idx: 1, complete: 1)

    scope :incomplete, proc { where(complete: false) }
    scope :complete,   proc { where(complete: true) }

    before_create { self.id_count = ids.count }

    # TODO - expire data
  end
end
