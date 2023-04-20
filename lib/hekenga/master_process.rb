module Hekenga
  class MasterProcess
    def initialize(migration)
      @migration = migration
    end

    def run!
      Hekenga.log "Launching migration #{@migration.to_key}: #{@migration.description}"
      @migration.tasks.each.with_index do |task, idx|
        launch_task(task, idx)
        report_while_active(task, idx)
      ensure
        @active_thread = nil
      end
    end

    def report_while_active(task, idx)
      # Wait for the log to be generated
      until (@migration.log(idx) rescue nil)
        sleep 1
      end
      # Periodically report on thread progress
      until @migration.log(idx).reload.done || !@active_thread.alive?
        @active_thread.join if @active_thread.alive?
        report_status(task, idx)
        sleep Hekenga.config.report_sleep
      end
      report_status(task, idx) if task.is_a?(Hekenga::DocumentTask)
      report_result(task, idx)
      Hekenga.log "Completed"
    end

    private

    def launch_task(task, idx)
      Hekenga.log "Launching task##{idx}: #{task.description}"
      @active_thread = Thread.new do
        @migration.perform_task!(idx)
      end.tap do |t|
        #t.report_on_exception = false
        t.abort_on_exception = true
      end
    end

    def report_status(task, idx)
      case task
      when Hekenga::DocumentTask
        if task.parallel
          Hekenga.log "#{@migration.task_records(idx).count} batches queued, #{@migration.task_records(idx).complete.count} completed"
        else
          Hekenga.log "#{@migration.task_records(idx).complete.count} batches processed"
        end
      when Hekenga::SimpleTask
        Hekenga.log "Waiting for task to complete"
      end
    end

    def report_result(task, idx)
      case task
      when Hekenga::DocumentTask
        Hekenga.log "Migration result:"
        combined_stats(idx)&.each do |stat, count|
          Hekenga.log " - #{stat.capitalize}: #{count}"
        end
      when Hekenga::SimpleTask
        report_simple_result(idx)
      end
    end

    def combined_stats(idx)
      Hekenga::DocumentTaskRecord.collection.aggregate([
        { "$match" => @migration.task_records(idx).selector },
        { "$group" => {
          "_id" => "1",
          "failed" => { "$sum" => "$stats.failed" },
          "invalid" => { "$sum" => "$stats.invalid" },
          "written" => { "$sum" => "$stats.written" },
        }}
      ]).to_a[0]&.except("_id")
    end

    def report_simple_result(idx)
      if @migration.log(idx).failures.any?
        Hekenga.log "The task crashed with the following error message:"
        @migration.log(idx).failures.each do |failure|
          Hekenga.log failure.message
        end
        exit(1)
      else
        Hekenga.log "Task succeeded"
      end
    end
  end
end
