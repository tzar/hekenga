module Hekenga
  class DocumentTaskExecutor
    attr_reader :record
    attr_reader :context, :session

    def initialize(record)
      @record = record
    end

    def run!
      with_setup do |context|
        with_transaction do |session|
          process_batch
        end
      end
    end

    private

    def process_batch
      # TODO
      # - filter records
      # - clone + migration records
      # - filter unchanged (maybe)
      # - validate records (maybe)
      # - write records
      # - write result
    end

    def migration
      @migration ||= Hekenga.find_migration(record.migration_key)
    end

    def with_setup(&block)
      @context = Hekenga::Context.new(migration)
      task.setups&.each do |setup|
        @context.instance_exec(&setup)
      end
      yield
    ensure
      @context = nil
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
        @abort_transaction = false
        yield
        if record.test_mode || @abort_transaction
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
      @task ||= @migration.tasks[record.task_id]
    end
  end
end
