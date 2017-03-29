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
  end
end
require 'hekenga/failure/error'
require 'hekenga/failure/write'
require 'hekenga/failure/validation'
