module Hekenga
  class DocumentTaskExecutor
    attr_reader :task_record
    attr_reader :context, :session

    def initialize(task_record, records: nil)
      @task_record       = task_record
      @records           = records
      @migrated_records  = []
      @invalid_records   = []
      @records_to_write  = []
      @filtered_records  = []
      @skipped_records   = []
      @failed_records    = []
      @backed_up_records = {}
    end

    def run!
      with_setup do |context|
        with_transaction do |session|
          filter_records
          run_migration
          validate_records
          write_records
          write_result unless task_record.test_mode
        end
        # In test mode, the transaction will be aborted - so we need to write
        # the result outside of the run! block
        write_result if task_record.test_mode
      end
    end

    def check_for_completion!
      if migration_complete?
        migration.log(task_idx).set_without_session(
          done: true,
          finished: Time.now,
          error: migration.task_records(task_idx).failed.any?
        )
      end
    end

    def migration_cancelled?
      migration.log(task_idx).cancel
    end

    private

    delegate :task_idx, to: :task_record

    attr_reader :migrated_records, :records_to_write, :filtered_records, :invalid_records, :skipped_records, :failed_records, :backed_up_records

    def migration_complete?
      migration.task_records(task_idx).incomplete.none?
    end

    def record_scope
      task.scope.klass.unscoped.in(_id: task_record.ids)
    end

    def records
      @records ||= record_scope.to_a
    end

    def write_result
      task_record.update_attributes(
        complete: true,
        finished: Time.now,
        failed_ids: failed_records.map(&:_id),
        invalid_ids: invalid_records.map(&:_id),
        written_ids: records_to_write.map(&:_id),
        stats: {
          failed: failed_records.length,
          invalid: invalid_records.length,
          written: records_to_write.length
        }
      )
    end

    def filter_records
      records.each do |record|
        if task.filters.all? {|block| context.instance_exec(record, &block)}
          filtered_records << record
        else
          skipped_records << record
        end
      rescue => _e
        failed_records << record
      end
    end

    def run_migration
      filtered_records.each do |record|
        backup_record(record)
        task.up!(@context, record)
        migrated_records << record
      rescue => _e
        failed_records << record
      end
    end

    def backup_record(record)
      return unless task.write_strategy == :delete_then_insert

      backed_up_records[record._id] = record.as_document.deep_dup
    end

    def validate_records
      migrated_records.each do |record|
        if record.valid?
          records_to_write << record
        else
          invalid_records << record
        end
      end
    end

    def write_records
      records_to_write.keep_if(&:changed?) unless task.always_write
      return if records_to_write.empty?
      return if task_record.test_mode

      records_to_write.each {|record| record.send(:prepare_update) {}}

      case task.write_strategy
      when :delete_then_insert
        delete_then_insert_records
      else
        replace_records
      end
    rescue Mongo::Error::BulkWriteError => e
      # If we're in a transaction, we can retry; so just re-raise
      raise if @session
      # Otherwise, we need to log the failure
      write_failure!(e)
    end

    def write_failure!(error)
      log = migration.log(task_idx)
      backups = records_to_write.map do |record|
        failed_records << record
        backed_up_records[record._id]
      end.compact
      @records_to_write = []
      log.add_failure({
        message:   error.to_s,
        backtrace: error.backtrace,
        documents: backups,
        document_ids: records_to_write.map(&:_id),
        task_record_id: task_record.id
      }, Hekenga::Failure::Write)
      log.set_without_session({error: true})
    end

    def delete_then_insert_records
      operations = []
      operations << {
        delete_many: {
          filter: {
            _id: {
              '$in': records_to_write.map(&:_id)
            }
          }
        }
      }
      records_to_write.each do |record|
        operations << { insert_one: record.as_document }
      end
      bulk_write(operations, ordered: true)
    end

    def bulk_write(operations, **options)
      task.scope.klass.collection.bulk_write(operations, session: session, **options)
    end

    def replace_records
      operations = records_to_write.map do |record|
        {
          replace_one: {
            filter: { _id: record._id },
            replacement: record.as_document
          }
        }
      end
      bulk_write(operations)
    end

    def migration
      @migration ||= Hekenga.find_migration(task_record.migration_key)
    end

    def with_setup(&block)
      @context = Hekenga::Context.new(test_mode: task_record.test_mode)
      begin
        task.setups&.each do |setup|
          @context.instance_exec(&setup)
        end
      rescue => e
        fail_and_cancel!(e)
        return
      end
      yield
    ensure
      @context = nil
    end

    def fail_and_cancel!(error)
      log = migration.log(task_idx)
      log.add_failure({
        message:   error.to_s,
        backtrace: error.backtrace
      }, Hekenga::Failure::Error)
      log.set_without_session({cancel: true, error: true, done: true, finished: Time.now})
      task_record.update_attributes(
        complete: true,
        finished: Time.now,
        failed_ids: task_record.ids,
        invalid_ids: [],
        written_ids: [],
        stats: {
          failed: task_record.ids.length,
          invalid: 0,
          written: 0,
        }
      )
    end

    def with_transaction(&block)
      return yield unless task.use_transaction

      ensure_replicaset!
      klass = task.scope.klass
      # NOTE: Dummy session to work around threading bug
      klass.persistence_context.client.start_session({})
      klass.with_session do |session|
        @session = session
        @session.start_transaction
        yield
        if task_record.test_mode
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

    def ensure_replicaset!
      return unless task.use_transaction

      unless task.scope.klass.collection.client.cluster.replica_set?
        raise "MongoDB must be in a replica set to use transactions"
      end
    end

    def task
      @task ||= migration.tasks[task_idx]
    end
  end
end
