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
    field :total
    field :processed, default: 0
    field :skipped,   default: 0
    field :unvalid,   default: 0
    field :started,   default: ->{ Time.now }
    field :finished,  type:    Time

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

    def incr_and_return(fields)
      doc = self.class.where(_id: self.id).find_one_and_update(
        {'$inc': fields},
        return_document: :after,
        projection: fields.keys.map {|x| [x, 1]}.to_h,
        session: nil
      )
      fields.map do |field, _|
        value = doc.send(field)
        send("#{field}=", value)
        [field, value]
      end.to_h
    end
  end
end
