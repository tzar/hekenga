module Hekenga
  class ParallelTask
    attr_reader :migration, :task, :task_idx

    def initialize(migration:, task:, task_idx:, test_mode:)
      @migration = migration
      @task      = task
      @task_idx  = task_idx
    end

    def start!
      clear_task_records!
      @executor_key = BSON::ObjectId.new
      Hekenga::Iterator.new(scope, size: 100_000).each do |id_block|
        task_records = id_block.each_slice(batch_size).map do |id_slice|
          generate_parallel_record(id_slice)
        end
        write_task_records!(task_records)
        queue_jobs!(task_records)
      end
      check_for_completion!
    end

    def resume!
      @executor_key = BSON::ObjectId.new
      task_records.set(executor_key: @executor_key)
      queue_jobs!(task_records.incomplete)
      check_for_completion!
    end

    def complete?
      task_records.incomplete.none?
    end

    def stats
      {
        total:   task_records.count,
        pending: task_records.incomplete.count,
        failed:  task_records.failed.count
      }
    end

    def check_for_completion!
      if complete?
        migration.log(task_idx).set_without_session(done: true, finished: Time.now)
      end
    end

    private

    def batch_size
      task.batch_size || migration.batch_size
    end

    def clear_task_records!
      task_records.delete_all
    end

    def task_records
      Hekenga::DocumentTaskRecord.where(migration_key: migration.to_key, task_idx: task_idx)
    end

    def generate_task_records!(id_slice)
      Hekenga::DocumentTaskRecord.new(
        migration_key: migration.to_key,
        task_idx:      task_idx,
        executor_key:  @executor_key,
        test_mode:     test_mode,
        ids:           id_slice
      ).tap do |record|
        record.send(:prepare_insert) {}
      end
    end

    def write_task_records!(records)
      Hekenga::DocumentTaskRecord.collection.bulk_write(records.map do |record|
        { insert_one: record.as_document }
      end)
    end

    def queue_jobs!(records)
      records.each do |record|
        Hekenga::ParallelJob.perform_async(record.id, @executor_key)
      end
    end
  end
end
