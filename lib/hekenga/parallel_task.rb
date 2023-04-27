require 'hekenga/iterator'
require 'hekenga/document_task_executor'
require 'hekenga/task_splitter'

module Hekenga
  class ParallelTask
    attr_reader :migration, :task, :task_idx, :test_mode

    def initialize(migration:, task:, task_idx:, test_mode:)
      @migration = migration
      @task      = task
      @task_idx  = task_idx
      @test_mode = test_mode
    end

    def start!
      clear_task_records!
      @executor_key = BSON::ObjectId.new
      generate_for_scope(task.scope)
      check_for_completion!
    end

    def resume!
      @executor_key = BSON::ObjectId.new
      task_records.set(executor_key: @executor_key)
      queue_jobs!(task_records.incomplete)
      generate_new_records!
      recover_failed_records!
      check_for_completion!
    end

    def complete?
      task_records.incomplete.none?
    end

    def check_for_completion!
      if complete?
        migration.log(task_idx).set_without_session(done: true, finished: Time.now)
      end
    end

    private

    def generate_for_scope(scope)
      Hekenga::Iterator.new(scope, size: 100_000).each do |id_block|
        task_records = id_block.each_slice(batch_size).map do |id_slice|
          generate_task_records!(id_slice)
        end
        write_task_records!(task_records)
        queue_jobs!(task_records)
      end
    end

    def generate_new_records!
      last_record = task_records.desc(:_id).first
      last_id = last_record&.ids&.last
      scope = task.scope
      scope = task.scope.and(_id: {'$gt': last_id}) if last_id
      generate_for_scope(scope)
    end

    # Any records with a failure or a validation failure get moved into
    # a new task record which is incomplete and gets a job queued
    def recover_failed_records!
      task_records.complete.no_timeout.each do |record|
        Hekenga::TaskSplitter.new(record, @executor_key).call.tap do |new_record|
          next if new_record.nil?

          Hekenga::ParallelJob.perform_later(new_record.id.to_s, @executor_key.to_s)
        end
      end
    end

    def batch_size
      task.batch_size || migration.batch_size
    end

    def clear_task_records!
      task_records.delete_all
    end

    def task_records
      migration.task_records(task_idx)
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
        Hekenga::ParallelJob.perform_later(record.id.to_s, @executor_key.to_s)
      end
    end
  end
end
