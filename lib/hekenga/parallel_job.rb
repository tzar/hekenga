require 'active_job'
module Hekenga
  class ParallelJob < ActiveJob::Base
    queue_as :migration
    def perform(migration_key, task_idx, ids)
      migration = Hekenga.find_migration(migration_key)
      migration.run_parallel_task(task_idx, ids)
    end
  end
end
