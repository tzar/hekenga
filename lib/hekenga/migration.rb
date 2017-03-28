require 'hekenga/invalid'
require 'hekenga/context'
require 'hekenga/parallel_job'
module Hekenga
  class Migration
    attr_accessor :stamp, :description, :skip_prepare, :batch_size
    attr_reader :tasks

    def initialize
      @tasks = []
      @batch_size = 25
    end

    # Internal
    def timestamp
      self.stamp.strftime("%Y-%m-%dT%H:%M")
    end

    def desc_to_token
      @desc_to_token ||= self.description.gsub(/[^A-Za-z]+/,"_").gsub(/(^_|_$)/,"")
    end

    def inspect
      "<Hekenga::Migration #{self.to_key}>"
    end

    def to_key
      @pkey ||= "#{timestamp}-#{desc_to_token}"
    end

    def log
      @log ||= Hekenga::Log.where(pkey: self.to_key).first
    end

    # API
    def reload_log
      log.reload
    end
    def performing?
      !!log.started && !performed?
    end
    def performed?
      !!log.done
    end
    def perform!(task_idx = 0)
      task = @tasks[task_idx] or return
      case task
      when Hekenga::SimpleTask
        task.up!
        perform!(task_idx + 1)
      when Hekenga::DocumentTask
        if task.parallel
          start_parallel_task(task, task_idx)
          # Parallel task will queue the next task when done
        else
          start_document_task(task, task_idx)
          perform!(task_idx + 1)
        end
      end
    end
    def recover!
      # TODO
    end
    def report!
      # TODO
    end
    def rollback!
      # TODO
    end

    # Internal perform methods
    def start_parallel_task(task, task_idx)
      task.scope.pluck(:_id).each_slice(batch_size).each do |ids|
        Hekenga::ParallelJob.perform_later(
          self.to_key, task_idx, ids
        )
      end
    end
    def run_parallel_task(task_idx, ids)
      # TODO - check for cancellation
      task = self.tasks[task_idx] or return
      with_setup(task) do
        process_batch(task, task.scope.in(_id: ids).to_a)
      end
    end
    def with_setup(task)
      @context = Hekenga::Context.new
      setups.each do |block|
        @context.instance_exec(&block)
      end
      # Disable specific callbacks
      begin
        task.disable_rules.each do |rule|
          rule[:klass].skip_callback rule[:callback]
        end
        yield
      ensure
        @context = nil
        # Make sure the callbacks make it back
        task.disable_rules.each do |rule|
          rule[:klass].set_callback rule[:callback]
        end
      end
    end
    def start_document_task(task, task_idx)
      records = []
      with_setup(task) do
        task.scope.asc(:_id).each do |record|
          records.push(record)
          if records.length == BATCH_SIZE
            process_batch(task, records)
            records = []
          end
        end
        process_batch(task, records) if records.any?
      end
    end
    def run_filters(task, record)
      task.filters.all? do |block|
        instance_exec(record, &block)
      end
    end
    def process_batch(task, records)
      to_persist = []
      fallbacks  = []

      records.map do |record|
        unless run_filters(task, record)
          log_skipped(task, record)
          next
        end
        original_record = Marshal.load(Marshal.dump(record.as_document))
        task.up!(@context, record)
        if validate_record(record)
          to_persist.push(record)
          fallbacks.push(original_record)
        end
      end.compact
      persist_batch(task, to_persist, fallbacks)
    end
    def log_skipped(task, record)
      # TODO
    end
    def log_success(task, records)
      # TODO
    end

    def persist_batch(task, records, original_records)
      records.each do |record|
        if skip_prepare
          # NOOP - we skip the prepare_update phase and just use the document
          # directly
        elsif task.timeless
          record.timeless.send(:prepare_update) {}
        else
          record.send(:prepare_update) {}
        end
      end
      begin
        task.scope.klass.in(_id: records.map(&:_id)).delete_all
        task.scope.klass.collection.insert_many(records.map(&:as_document))
        log_success(task, records)
      rescue => e
        failed_write!(e, original_records)
      end
    end
    def failed_write!(error, original_records)
      # TODO - dump original_records + error to log, cancel w catastrophic failure
    end
    def validate_record(record)
      if record.valid?
        true
      else
        # TODO - log invalid
        false
      end
    end

    # Validations
    MIN_TOKEN_LENGTH = 5

    def validation_error(field, reason)
      raise Hekenga::Invalid.new(self, field, reason)
    end

    def validate!
      validation_error(:stamp,       "missing")   unless self.stamp.is_a?(Time)
      validation_error(:description, "missing")   unless self.description
      validation_error(:description, "too short") unless self.desc_to_token.length > 5
      validation_error(:tasks,       "missing")   if self.tasks.length.zero?
      true
    end
  end
end
