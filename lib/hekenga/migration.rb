require 'hekenga/invalid'
require 'hekenga/context'
require 'hekenga/parallel_job'
require 'hekenga/master_process'
require 'hekenga/log'
module Hekenga
  class Migration
    attr_accessor :stamp, :description, :batch_size
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

    def perform_task!(task_idx = 0, scope = nil)
      task         = @tasks[task_idx] or return
      @active_idx  = task_idx
      case task
      when Hekenga::SimpleTask
        start_simple_task(task)
      when Hekenga::DocumentTask
        # TODO - online migration support (have log.total update, requeue)
        scope ||= task.scope.asc(:_id)
        ensure_replicaset!(task)
        if task.parallel
          start_parallel_task(task, task_idx, scope)
        else
          start_document_task(task, task_idx, scope)
        end
      end
    end

    def recover!
      # NOTE - can't find a way to check this automatically with ActiveJob right now
      return false unless prompt "Check that the migration queue has processed before recovering. Continue?"
      # Write failures
      @tasks.each.with_index do |task, idx|
        # If no log, run the task now
        unless Hekenga::Log.where(pkey: self.to_key, task_idx: idx).any?
          return false unless retry_task!(task, idx)
          next
        end
        # Did this task fail?
        failedP = log(idx).cancel || Hekenga::Failure.where(pkey: to_key, task_idx: idx).any?
        # If it didn't, keep searching
        next unless failedP
        # This is the first failure we've detected - recover from it
        case task
        when Hekenga::DocumentTask
          ret = recover_document_task!(task, idx)
        when Hekenga::SimpleTask
          ret = recover_simple!(task, idx)
        end

        case ret
        when :next
          next
        when :cancel
          return false
        else
          return false unless retry_task!(task, idx, ret)
        end
      end
      return true
    end

    def retry_task!(task, idx, scope = nil)
      Hekenga.log "Retrying task##{idx}"
      unless Hekenga::MasterProcess.new(self).retry!(idx, scope)
        Hekenga.log "Failed to retry the task. Aborting.."
        return false
      end
      return true
    end

    def recover_simple!(task, idx)
      # Simple tasks just get retried - no fuss
      Hekenga.log("Found failed simple task. Retrying..")
      return
    end

    def recover_document_task!(task, idx)
      # Document tasks are a bit more involved.
      validation_failures = Hekenga::Failure::Validation.where(pkey: to_key, task_idx: idx)
      write_failures      = Hekenga::Failure::Write.where(pkey: to_key, task_idx: idx)
      error_failures      = Hekenga::Failure::Error.where(pkey: to_key, task_idx: idx)
      cancelled_failures  = Hekenga::Failure::Cancelled.where(pkey: to_key, task_idx: idx)

      # Stats
      validation_failure_ctr = validation_failures.count
      write_failure_ctr      = write_failures.count
      error_failure_ctr      = error_failures.count
      cancelled_failure_ctr  = cancelled_failures.count

      # Prompt for recovery
      recoverP = prompt(
        "Found #{validation_failure_ctr} invalid, "+
        "#{write_failure_ctr} failed writes, "+
        "#{error_failure_ctr} errors, "+
        "#{cancelled_failure_ctr} cancelled on migration. Recover?"
      )
      return :next unless recoverP

      # Recover from critical write failures (DB records potentially lost)
      unless write_failure_ctr.zero?
        Hekenga.log "Recovering old data from #{write_failure_ctr} write failure(s)"
        recover_data(write_failures, task.scope.klass)
      end

      # Resume task from point of error
      if task.parallel
        # TODO - support for recovery on huge # IDs
        failed_ids = [
          write_failures.pluck(:document_ids),
          error_failures.pluck(:batch_start),
          cancelled_failures.pluck(:document_ids),
          validation_failures.pluck(:doc_id)
        ].flatten.compact
        resume_scope = task.scope.klass.asc(:_id).in(_id: failed_ids)
      else
        first_id     = error_failures.first&.batch_start || write_failures.first&.batch_start
        invalid_ids  = validation_failures.pluck(:doc_id)
        if first_id && invalid_ids.any?
          resume_scope = task.scope.klass.asc(:_id).and(
            task.scope.selector,
            task.scope.klass.or(
              {_id: {:$gte => first_id}},
              {_id: {:$in  => invalid_ids}}
            ).selector
          )
        elsif first_id
          resume_scope = task.scope.asc(:_id).gte(_id: first_id)
        elsif invalid_ids.any?
          resume_scope = task.scope.klass.asc(:_id).in(_id: invalid_ids)
        else
          resume_scope = :next
        end
      end

      return resume_scope
    end

    def recover_data(write_failures, klass)
      write_failures.each do |write_failure|
        failed_ids = write_failure.document_ids
        extant     = klass.in(_id: failed_ids).pluck(:_id)
        to_recover = (failed_ids - extant)
        docs       = write_failure.documents.find_all {|x| to_recover.include?(x["_id"])}
        next if docs.empty?
        Hekenga.log "Recovering #{docs.length} documents.."
        klass.collection.insert_many(docs)
      end
    end

    def prompt(str)
      loop do
        print "#{str} (Y/N):\n"
        case gets.chomp.downcase
        when "y"
          return true
        when "n"
          return false
        end
      end
    end

    def rollback!
      # TODO
    end

    # Internal perform methods
    def start_simple_task(task)
      create_log!
      begin
        with_setup do
          task.up!(@context)
        end
      rescue => e
        simple_failure!(e)
        return
      end
      log_done!
    end

    def check_for_completion
      if log.processed == log.total
        log_done!
      end
    end

    def log_done!
      log.set_without_session({done: true, finished: Time.now})
    end

    def start_parallel_task(task, task_idx, scope)
      # TODO - support for crazy numbers of documents where pluck is too big
      scope.asc(:_id).pluck(:_id).tap do |all_ids|
        create_log!(total: all_ids.length)
      end.each_slice(task.batch_size || batch_size).each do |ids|
        Hekenga::ParallelJob.perform_later(
          self.to_key, task_idx, ids.map(&:to_s), !!@test_mode
        )
      end
      check_for_completion # if 0 items to migrate
    end

    def run_parallel_task(task_idx, ids)
      @active_idx = task_idx
      if log(task_idx).cancel
        failed_cancelled!(ids)
        return
      end
      task = self.tasks[task_idx] or return
      with_setup(task) do
        process_batch(task, task.scope.klass.asc(:_id).in(_id: ids).to_a)
        unless @skipped.empty?
          failed_cancelled!(@skipped.map(&:_id))
        end
      end
    end

    def with_setup(task = nil)
      @context = Hekenga::Context.new(self)
      task&.setups&.each do |block|
        @context.instance_exec(&block)
      end
      begin
        yield
      ensure
        @context = nil
      end
    end

    def start_document_task(task, task_idx, scope)
      create_log!(total: scope.count)
      records = []
      with_setup(task) do
        scope.asc(:_id).no_timeout.each do |record|
          records.push(record)
          if records.length == (task.batch_size || batch_size)
            process_batch(task, records)
            return if log.cancel
            records = []
          end
        end
        process_batch(task, records) if records.any?
      end
      log_done!
    end

    def run_filters(task, record)
      task.filters.all? do |block|
        @context.instance_exec(record, &block)
      end
    end

    def deep_clone(record)
      record.as_document.deep_dup
    end

    def process_batch(task, records)
      with_transaction(task) do
        @skipped   = []
        to_persist = []
        fallbacks  = []

        filtered = records.group_by do |record|
          run_filters(task, record)
        end
        log_skipped(task, filtered[false]) if filtered[false]
        return unless filtered[true]
        filtered[true].map.with_index do |record, idx|
          original_record = deep_clone(record)
          begin
            task.up!(@context, record)
          rescue => e
            failed_apply!(e, record, records[0].id)
            @skipped = filtered[true]
            @abort_transaction = true
            return
          end
          if validate_record(task, record)
            to_persist.push(record)
            fallbacks.push(original_record)
          else
            if log.cancel
              @skipped = filtered[true]
              @abort_transaction = true
              return
            end
          end
        end.compact
        persist_batch(task, to_persist, fallbacks)
      end
    end

    def with_transaction(task, &block)
      return yield unless task.use_transaction

      ensure_replicaset!(task)
      klass = task.scope.klass
      # NOTE: Dummy session to work around threading bug
      klass.persistence_context.client.start_session({})
      klass.with_session do |session|
        @session = session
        @session.start_transaction
        @abort_transaction = false
        yield
        if @test_mode || @abort_transaction
          @session.abort_transaction
        else
          @session.commit_transaction
        end
      rescue
        @session.abort_transaction
        raise
      ensure
        @session = nil
      end
    end

    def ensure_replicaset!(task)
      return unless task.use_transaction

      unless task.scope.klass.collection.client.cluster.replica_set?
        raise "MongoDB must be in a replica set to use transactions"
      end
    end

    def log_skipped(task, records)
      log.incr_and_return({
        skipped:   records.length,
        processed: records.length
      })
      check_for_completion
    end

    def log_success(task, processed, skipped)
      log.incr_and_return({
        skipped: skipped,
        processed: processed
      })
      check_for_completion
    end

    def persist_batch(task, records, original_records)
      if task.always_write
        records_to_write = records
        unchanged_count = 0
      else
        records_to_write = records.filter(&:changed?)
        unchanged_count = records.length - records_to_write.length
      end
      if @test_mode
        log_success(task, records.length, unchanged_count)
        return
      end
      # NOTE - edgecase where callbacks cause the record to become invalid is
      # not covered
      records_to_write.each do |record|
        begin
          next if task.skip_prepare
          if task.timeless
            record.timeless.send(:prepare_update) {}
          else
            record.send(:prepare_update) {}
          end
        rescue => e
          # If prepare_update throws an error, we're in trouble - crash out now
          failed_apply!(e, record, records_to_write[0].id)
          @abort_transaction = true
          return
        end
      end
      begin
        write_result!(task, records_to_write)
        log_success(task, records.length, unchanged_count)
      rescue => e
        # If we're in a transaction, a failed write is retryable - crash so the
        # job will requeue
        raise e if session
        failed_write!(e, original_records)
      end
    end

    def write_result!(task, records)
      klass = task.scope.klass
      case task.write_strategy
      when :delete_then_insert
        delete_then_insert_records!(klass, records)
      else
        update_many!(klass, records)
      end
    end

    def update_many!(klass, records)
      return unless records.any?

      klass.collection.bulk_write(records.map do |record|
        {
          replace_one: {
            filter: { _id: record.id },
            replacement: record.as_document
          }
        }
      end, **bulk_options)
    end

    def delete_then_insert_records!(klass, records)
      return unless records.any?

      operations = [delete_operation(records)] + records.map do |record|
        { insert_one: record.as_document }
      end
      klass.collection.bulk_write(operations, ordered: true, **bulk_options)
    end

    def bulk_options
      return {} if session.nil?

      { session: session }
    end

    def delete_operation(records)
      {
        delete_many: {
          filter: {
            _id: {
              '$in': records.map(&:id)
            }
          }
        }
      }
    end

    def simple_failure!(error)
      log.add_failure({
        message:   error.to_s,
        backtrace: error.backtrace,
        simple:    true
      }, Hekenga::Failure::Error)
      log_cancel!
    end

    def failed_cancelled!(ids)
      log.add_failure({
        document_ids: ids,
        batch_start: ids[0]
      }, Hekenga::Failure::Cancelled)
    end

    def failed_apply!(error, record, batch_start_id)
      log.add_failure({
        message:     error.to_s,
        backtrace:   error.backtrace,
        document:    deep_clone(record),
        batch_start: batch_start_id
      }, Hekenga::Failure::Error)
      log_cancel!
    end

    def log_cancel!
      # Bypass the active transaction if there is one
      log.set_without_session({cancel: true, error: true, done: true, finished: Time.now})
    end

    def failed_write!(error, original_records)
      log.add_failure({
        message:      error.to_s,
        backtrace:    error.backtrace,
        documents:    original_records,
        document_ids: original_records.map {|x| x["_id"]},
        batch_start:  original_records[0]["_id"]
      }, Hekenga::Failure::Write)
      log_cancel!
    end

    def failed_validation!(task, record)
      log.add_failure({
        doc_id:   record.id,
        errs:     record.errors.full_messages,
        document: deep_clone(record),
      }, Hekenga::Failure::Validation)
      log.set_without_session({error: true})
      log.incr_and_return({processed: 1, unvalid: 1})
      if task.invalid_strategy == :cancel
        log_cancel!
      else
        check_for_completion
      end
    end

    def validate_record(task, record)
      # TODO - ability to skip validation
      # TODO - handle errors on validation
      if record.valid?
        true
      else
        failed_validation!(task, record)
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
