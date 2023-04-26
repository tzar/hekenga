require 'hekenga/task_failed_error'
require 'hekenga/task_splitter'

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
      rescue Hekenga::TaskFailedError
        return false
      ensure
        @active_thread = nil
      end
      true
    end

    def recover!
      Hekenga.log "Recovering migration #{@migration.to_key}: #{@migration.description}"
      @migration.tasks.each.with_index do |task, idx|
        recover_task(task, idx)
        report_while_active(task, idx)
      rescue Hekenga::TaskFailedError
        return false
      ensure
        @active_thread = nil
      end
      true
    end

    def report_while_active(task, idx)
      # Wait for the log to be generated
      until (@migration.log(idx) rescue nil)
        sleep 1
      end
      # Periodically report on thread progress
      until @migration.log(idx).reload.done
        @active_thread.join
        report_status(task, idx)
        sleep Hekenga.config.report_sleep
      end
      report_status(task, idx) if task.is_a?(Hekenga::DocumentTask)
      report_result(task, idx)
      Hekenga.log "Completed"
    end

    private

    def recover_task(task, idx)
      case task
      when Hekenga::DocumentTask
        recover_document_task(task, idx)
      when Hekenga::SimpleTask
        recover_simple_task(task, idx)
      end
    end

    def recover_document_task(task, idx)
      log = @migration.log(idx) rescue nil
      if document_task_failed?(log, idx)
        Hekenga.log "Recovering task##{idx}: #{task.description}"
        log.set_without_session({
          done: false,
          error: false,
          cancel: false,
          finished: nil,
        })
        recover_write_failures(task, log)
        task_records = @migration.task_records(idx)
        if task.parallel
          Hekenga::ParallelTask.new(
            migration: @migration,
            task: task,
            task_idx: idx,
            test_mode: @migration.test_mode
          ).resume!
        else
          # Strategy: clear failures; reset state
          log.failures.delete_all
          task_records.incomplete.delete_all
          task_records.each do |record|
            Hekenga::TaskSplitter.new(record, @executor_key).call&.destroy
          end
          @migration.active_idx = idx
          in_thread do
            @migration.start_document_task(task, idx, recover: true)
          end
        end

      else
        Hekenga.log "Skipping completed task##{idx}: #{task.description}"
      end
    end

    def document_task_failed?(log, idx)
      return true if log.nil?
      return true if log.error
      stats = combined_stats(idx)
      return false if stats.blank?
      return true if stats['failed'] > 0
      return true if stats['invalid'] > 0
      false
    end

    def recover_write_failures(task, log)
      klass = task.scope.klass
      log.failures.where(_type: "Hekenga::Failure::Write").each do |write_failure|
        next unless write_failure.documents.any?

        existing = klass.in(_id: write_failure.documents.map {|doc| doc["_id"]}).pluck(:_id).to_set
        to_write = write_failure.documents.reject {|doc| existing.include?(doc["_id"])}
        next if to_write.empty?

        Hekenga.log("Recovering #{to_write.length} write failures")
        klass.collection.insert_many(to_write)
      end.delete_all
    end

    def recover_simple_task(task, idx)
      log = @migration.log(idx) rescue nil
      if log.nil?
        Hekenga.log "Recovering task##{idx}: #{task.description}"
        launch_task(task, idx)
      elsif log.error
        Hekenga.log "Recovering task##{idx}: #{task.description}"
        # Strategy: clear logs + rerun
        log.failures.delete_all
        log.destroy
        @migration.reload_logs
        launch_task(task, idx)
      else
        Hekenga.log "Skipping completed task##{idx}: #{task.description}"
      end
    end

    def launch_task(task, idx)
      Hekenga.log "Launching task##{idx}: #{task.description}"
      in_thread do
        @migration.perform_task!(idx)
      end
    end

    def in_thread(&block)
      @active_thread = Thread.new(&block).tap do |t|
        t.report_on_exception = false
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
        end&.tap do |stats|
          if stats['failed'] > 0
            Hekenga.log "There were failures while running the task. Stopping"
            raise Hekenga::TaskFailedError
          end
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
        raise Hekenga::TaskFailedError
      else
        Hekenga.log "Task succeeded"
      end
    end
  end
end
