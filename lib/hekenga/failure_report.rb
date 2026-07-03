module Hekenga
  class FailureReport
    def initialize(migration)
      @migration = migration
    end

    # Per-task summaries for document tasks that have any failed or invalid
    # document IDs.
    # => [{ idx:, description:, failed_ids: [...], invalid_ids: [...] }, ...]
    def tasks
      @migration.tasks.each.with_index.filter_map do |task, idx|
        next unless task.is_a?(Hekenga::DocumentTask)

        records = @migration.task_records(idx).any_of(
          { :failed_ids.ne  => [] },
          { :invalid_ids.ne => [] }
        )

        failed_ids  = []
        invalid_ids = []
        records.pluck(:failed_ids, :invalid_ids).each do |failed, invalid|
          failed_ids.concat(failed)   if failed
          invalid_ids.concat(invalid) if invalid
        end
        next if failed_ids.empty? && invalid_ids.empty?

        {
          idx:         idx,
          description: task.description,
          failed_ids:  failed_ids,
          invalid_ids: invalid_ids
        }
      end
    end

    def print!
      Hekenga.log("Failures for #{@migration.to_key}")

      summaries = tasks
      if summaries.empty?
        Hekenga.log("  No failed or invalid documents.")
        return
      end

      failed_ids  = summaries.flat_map { |summary| summary[:failed_ids] }
      invalid_ids = summaries.flat_map { |summary| summary[:invalid_ids] }

      print_ids("Failed",  failed_ids)
      print_ids("Invalid", invalid_ids)
    end

    private

    def print_ids(label, ids)
      return if ids.empty?

      Hekenga.log("    #{label} (#{ids.length}): #{ids.map { |id| "\"#{id}\"" }.join(", ")}")
    end
  end
end
