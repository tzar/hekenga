module Hekenga
  class TaskSplitter
    attr_reader :record, :executor_key

    def initialize(record, executor_key)
      @record = record
      @executor_key = executor_key
    end

    def call
      return if record.failed_ids.blank? && record.invalid_ids.blank?

      Hekenga::DocumentTaskRecord.new.tap do |new_record|
        new_record.migration_key = record.migration_key
        new_record.task_idx = record.task_idx
        new_record.executor_key = executor_key
        new_record.ids = record.failed_ids | record.invalid_ids
        new_record.save!

        record.ids -= new_record.ids
        record.failed_ids = []
        record.invalid_ids = []
        record.id_count = record.ids.count
        record.stats = record.stats.merge('failed' => 0, 'invalid' => 0)
        record.save!
      end
    end
  end
end

