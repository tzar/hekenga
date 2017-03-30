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
      self.failures.create({
        pkey:     self.pkey,
        task_idx: self.task_idx
      }.merge(attrs), klass)
    end

    def incr_and_return(fields)
      doc = self.class.where(_id: self.id).find_one_and_update({
        :$inc => fields
      }, return_document: :after, projection: fields.keys.map {|x| [x, 1]}.to_h)
      fields.map do |field, _|
        value = doc.send(field)
        send("#{field}=", value)
        [field, value]
      end.to_h
    end
  end
end
