module Hekenga
  class DocumentTaskRecord
    include Mongoid::Document

    field :migration_key, type: String
    field :task_idx, type: Integer
    field :executor_key, type: BSON::ObjectId
    field :finished, type: Time
    field :status, type: String, default: "queued"
    field :ids, type: Array, default: []
    field :id_count, type: Integer
    field :test_mode, type: Boolean

    index(migration_key: 1, task_idx: 1, status: 1)
    index(migration_key: 1, task_idx: 1, ids: 1)

    scope :incomplete, proc { where(status: "queued") }
    scope :failed,     proc { where(status: "failed") }

    before_create { self.id_count = ids.count }
  end
end
