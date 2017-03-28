module Hekenga
  class Log
    include Mongoid::Document
    # Internal tracking
    field :pkey
    field :desc
    field :stamp

    # Status flags
    field :done,   default: false
    field :error,  default: false
    field :cancel, default: false

    # Used by simple tasks
    field :error_desc

    # Used by document tasks
    field :error_ids, default: []
    field :processed, default: 0
    field :started,   default: ->{ Time.now }
    field :finished,  type:    Time

    index({pkey: 1}, unique: true)

    def migration=(migration)
      self.pkey  = migration.to_key
      self.desc  = migration.desc
      self.stamp = migration.stamp
    end
  end
end
