require 'hekenga/invalid'
require 'hekenga/context'
require 'hekenga/parallel_job'
module Hekenga
  class Migration
    attr_accessor :stamp, :description, :skip_prepare, :batch_size
    attr_reader :tasks

    def initialize
      @tasks      = []
      @logs       = {}
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

    def log(task_idx = @active_idx)
      raise "Missing task index" if task_idx.nil?
      @logs[task_idx] ||= Hekenga::Log.find_by(
        pkey: self.to_key,
        task_idx: task_idx
      )
    end

    def create_log!(task_idx = @active_idx)
      @logs[task_idx] = Hekenga::Log.create(
        migration: self,
        task_idx:  task_idx
      )
    end

    # API
    def reload_logs
      @logs.each {|_, log| log.reload}
    end
    def performing?
      Hekenga::Log.where(pkey: self.to_key, done: false).any?
    end
    def performed?
      !!log(self.tasks.length - 1).done
    end
    def perform!(task_idx = 0)
      task = @tasks[task_idx] or return
      @active_idx = task_idx
      create_log!
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
      return if log(task_idx).cancel
      task = self.tasks[task_idx] or return
      @active_idx = task_idx
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
        @context.instance_exec(record, &block)
      end
    end
    def process_batch(task, records)
      to_persist = []
      fallbacks  = []

      filtered = records.partition do |record|
        run_filters(task, record)
      end
      log_skipped(task, filtered[false])
      return if filtered[true].empty?
      filtered[true].map do |record|
        original_record = Marshal.load(Marshal.dump(record.as_document))
        begin
          task.up!(@context, record)
        rescue => e
          failed_apply!(e, record, records[0].id)
          return
        end
        if validate_record(record)
          to_persist.push(record)
          fallbacks.push(original_record)
        end
      end.compact
      persist_batch(task, to_persist, fallbacks)
    end
    def log_skipped(task, records)
      log.incr_and_return(
        skipped:   records.length,
        processed: records.length
      )
    end
    def log_success(task, records)
      log.incr_and_return(
        processed: records.length
      )
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
    def failed_apply!(error, record, batch_start_id)
      log.add_failure({
        message:     error.to_s,
        backtrace:   error.backtrace,
        document:    Marshal.load(Marshal.dump(record.as_document)),
        batch_start: batch_start_id
      }, Hekenga::Failure::Error)
      log.set(cancel: true, error: true, done: true)
    end
    def failed_write!(error, original_records)
      log.add_failure({
        message:     error.to_s,
        backtrace:   error.backtrace,
        documents:   original_records,
        batch_start: original_records[0]["_id"]
      }, Hekenga::Failure::Write)
      log.set(cancel: true, error: true, done: true)
    end
    def failed_validation!(record)
      log.add_failure({
        doc_id:   record.id,
        errors:   record.full_errors,
        document: Marshal.load(Marshal.dump(record.as_document))
      }, Hekenga::Failure::Validation)
      log.set(error: true)
      log.incr_and_return(processed: 1, invalid: 1)
    end
    def validate_record(record)
      # TODO - ability to skip validation
      if record.valid?
        true
      else
        failed_validation!(record)
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
