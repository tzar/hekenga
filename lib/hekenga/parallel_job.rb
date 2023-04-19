require 'active_job'
module Hekenga
  class ParallelJob < ActiveJob::Base
    queue_as do
      ENV["HEKENGA_QUEUE"] || :migration
    end
    def perform(document_task_record_id, executor_key)
      record = Hekenga::DocumentTaskRecord.where(_id: document_task_record_id).first
      return if record.nil?
      return if record.executor_key != executor_key

      Hekenga::DocumentTaskExecutor.new(record).run!
    end
  end
end
