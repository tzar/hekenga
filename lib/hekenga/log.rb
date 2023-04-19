require 'hekenga/failure'

module Hekenga
  class Log
    include Mongoid::Document
    # Internal tracking
    field :pkey
    field :description
    field :stamp
    field :task_idx

    validates_presence_of [:pkey, :description, :stamp, :task_idx]

    # Status flags
    field :done,   default: false
    field :error,  default: false
    field :cancel, default: false
    field :skip,   default: false

    # Used by document tasks
    field :finished, type: Time

    has_many :failures, class_name: "Hekenga::Failure"

    index({pkey: 1, task_idx: 1}, unique: true)

    def migration=(migration)
      self.pkey        = migration.to_key
      self.description = migration.description
      self.stamp       = migration.stamp
    end

    def add_failure(attrs, klass)
      failure = klass.new(attrs.merge(pkey: pkey, task_idx: task_idx, log_id: _id))
      failure.send(:prepare_insert) {}
      Hekenga::Failure.collection.insert_one(
        failure.as_document,
        session: nil
      )
    end

    def set_without_session(attrs)
      self.class.collection.update_one(
        { _id: _id },
        {'$set': attrs},
        session: nil
      )
      self.attributes = attrs
    end
  end
end
