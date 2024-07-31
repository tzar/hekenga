require 'hekenga/invalid'
require 'hekenga/context'
require 'hekenga/parallel_job'
require 'hekenga/parallel_task'
require 'hekenga/mongoid_iterator'
require 'hekenga/master_process'
require 'hekenga/document_task_record'
require 'hekenga/document_task_executor'
require 'hekenga/log'
module Hekenga
  class Migration
    attr_accessor :stamp, :description, :batch_size, :active_idx
    attr_reader :tasks, :session, :test_mode

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

    def create_log!(attrs = {})
      @logs[@active_idx] = Hekenga::Log.create(attrs.merge(
        migration: self,
        task_idx:  @active_idx
      ))
    end

    # API
    def reload_logs
      @logs = {}
    end

    def performing?
      Hekenga::Log.where(pkey: self.to_key, done: false).any?
    end

    def performed?
      !!log(self.tasks.length - 1).done
    end

    def test_mode!
      @test_mode = true
    end

    def perform!
      if Hekenga.status(self) == :naught
        Hekenga::MasterProcess.new(self).run!
      else
        Hekenga.log "This migration has already been run! Aborting."
        return false
      end
    end

    def perform_task!(task_idx)
      task         = @tasks[task_idx] or return
      @active_idx  = task_idx
      case task
      when Hekenga::SimpleTask
        start_simple_task(task)
      when Hekenga::DocumentTask
        if task.parallel
          start_parallel_task(task, task_idx)
        else
          start_document_task(task, task_idx)
        end
      end
    end

    def recover!
      Hekenga::MasterProcess.new(self).recover!
    end

    # Internal perform methods
    def start_simple_task(task)
      create_log!
      begin
        @context = Hekenga::Context.new(test_mode: test_mode)
        task.up!(@context)
      rescue => e
        simple_failure!(e)
        return
      ensure
        @context = nil
      end
      log_done!
    end

    def log_done!
      log.set_without_session({done: true, finished: Time.now})
    end

    def start_parallel_task(task, task_idx)
      create_log!
      Hekenga::ParallelTask.new(
        migration: self,
        task:      task,
        task_idx:  task_idx,
        test_mode: test_mode
      ).start!
    end

    def task_records(task_idx)
      Hekenga::DocumentTaskRecord.where(migration_key: to_key, task_idx: task_idx)
    end

    def start_document_task(task, task_idx, recover: false)
      create_log!
      records = []
      task_records(task_idx).delete_all unless recover
      executor_key = BSON::ObjectId.new
      Hekenga::MongoidIterator.new(scope: task.scope, cursor_timeout: task.cursor_timeout).each do |record|
        records.push(record)
        next unless records.length == (task.batch_size || batch_size)

        records = filter_out_processed(task, task_idx, records)
        next unless records.length == (task.batch_size || batch_size)

        execute_document_task(task_idx, executor_key, records)
        records = []
        return if log.cancel
      end
      records = filter_out_processed(task, task_idx, records)
      execute_document_task(task_idx, executor_key, records) if records.any?
      return if log.cancel
      log_done!
    end

    def filter_out_processed(task, task_idx, records)
      return records if records.empty?

      selector = task_records(task_idx).in(ids: records.map(&:id))
      processed_ids = selector.pluck(:ids).flatten.to_set
      records.reject do |record|
        processed_ids.include?(record._id)
      end
    end

    def execute_document_task(task_idx, executor_key, records)
      task_record = Hekenga::DocumentTaskRecord.create(
        migration_key: to_key,
        task_idx: task_idx,
        executor_key: executor_key,
        test_mode: test_mode,
        ids: records.map(&:id)
      )
      Hekenga::DocumentTaskExecutor.new(task_record, records: records).run!
    end

    def simple_failure!(error)
      log.add_failure({
        message:   error.to_s,
        backtrace: error.backtrace,
        simple:    true
      }, Hekenga::Failure::Error)
      log_cancel!
    end

    def log_cancel!
      # Bypass the active transaction if there is one
      log.set_without_session({cancel: true, error: true, done: true, finished: Time.now})
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
