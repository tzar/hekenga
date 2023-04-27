require 'active_job'
module Hekenga
  class ParallelJob < ActiveJob::Base
    queue_as do
      ENV["HEKENGA_QUEUE"] || :migration
    end
    def perform(document_task_record_id, executor_key)
      record = Hekenga::DocumentTaskRecord.where(_id: document_task_record_id).first
      return if record.nil?
      return if record.executor_key != BSON::ObjectId(executor_key)
      return if record.complete?

      executor = Hekenga::DocumentTaskExecutor.new(record)
      return if executor.migration_cancelled?

      executor.run!
      executor.check_for_completion!
    end
  end
end
