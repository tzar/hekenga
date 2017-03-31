module Hekenga
  class Failure
    include Mongoid::Document
    belongs_to :log, class_name: "Hekenga::Log"

    # Internal tracking
    field :pkey
    field :task_idx

    validates_presence_of [:pkey, :task_idx, :log_id]

    index({pkey:   1})
    index({log_id: 1})

    def self.lookup(log_id, task_idx)
      where(log_id: log_id, task_idx: task_idx)
    end
  end
end
require 'hekenga/failure/error'
require 'hekenga/failure/write'
require 'hekenga/failure/validation'
