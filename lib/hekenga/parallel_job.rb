require 'active_job'
module Hekenga
  class ParallelJob < ActiveJob::Base
    queue_as do
      ENV["HEKENGA_QUEUE"] || :migration
    end
    def perform(migration_key, task_idx, ids, test_mode)
      migration = Hekenga.find_migration(migration_key)
      migration.test_mode! if test_mode
      migration.run_parallel_task(task_idx, ids)
    end
  end
end
