module Hekenga
  class MasterProcess
    def initialize(migration)
      @migration = migration
    end

    def run!
      Hekenga.log "Launching migration #{@migration.to_key}"
      @migration.tasks.each.with_index do |task, idx|
        launch_task(task, idx)
        report_while_active(task, idx)
        if @migration.log(idx).cancel
          Hekenga.log "TERMINATING DUE TO CRITICAL ERRORS"
          report_errors(idx)
          return
        elsif any_validation_errors?(idx)
          handle_validation_errors(task, idx)
          return if @migration.log(idx).cancel
        end
        cleanup
      end
    end

    def retry!(task_idx, scope)
      task = @migration.tasks[task_idx]
      # Reset logs completely
      Hekenga::Log.where(pkey: @migration.to_key, task_idx: task_idx).delete_all
      Hekenga::Failure.where(pkey: @migration.to_key, task_idx: task_idx).delete_all
      @migration.reload_logs
      # Start the task based on the passed scope - similar to run! but we exit
      # directly on failure.
      launch_task(task, task_idx, scope)
      report_while_active(task, task_idx)
      if @migration.log(task_idx).cancel
        return false
      elsif any_validation_errors?(task_idx)
        handle_validation_errors(task, task_idx)
        if @migration.log(task_idx).cancel
          return false
        end
      end
      cleanup
      true
    end

    def any_validation_errors?(idx)
      Hekenga::Failure::Validation.where(pkey: @migration.to_key, task_idx: idx).any?
    end

    def handle_validation_errors(task, idx)
      return unless task.respond_to?(:invalid_strategy)
      return if idx == @migration.tasks.length - 1
      case task.invalid_strategy
      when :prompt
        unless continue_prompt?("There were validation errors in the last task.")
          @migration.log(idx).set(cancel: true)
          return
        end
      when :stop
        Hekenga.log "TERMINATING DUE TO VALIDATION ERRORS"
        @migration.log(idx).set(cancel: true)
        return
      end
    end

    def report_errors(idx)
      scope  = @migration.log(idx).failures
      log_id = @migration.log(idx).id
      # Validation errors
      valid_errs     = scope.where(_type: "Hekenga::Failure::Validation")
      valid_errs_ctr = valid_errs.count
      unless valid_errs_ctr.zero?
        Hekenga.log "#{valid_errs_ctr} records failed validation. To get a list:"
        Hekenga.log "Hekenga::Failure::Validation.lookup('#{log_id}', #{idx})"
      end
      # Write failures
      write_errs     = scope.where(_type: "Hekenga::Failure::Write")
      write_errs_ctr = write_errs.count
      unless write_errs_ctr.zero?
        Hekenga.log "#{write_errs_ctr} write errors detected. Error messages:"
        Hekenga.log(write_errs.pluck(:message).uniq.map {|x| "- #{x}"}.join("\n"))
        Hekenga.log "To get a list:"
        Hekenga.log "Hekenga::Failure::Write.lookup('#{log_id}', #{idx})"
        # TODO - recover message
      end
      # Migration errors
      general_errs     = scope.where(_type: "Hekenga::Failure::Error")
      general_errs_ctr = general_errs.count
      unless general_errs_ctr.zero?
        Hekenga.log "#{general_errs_ctr} migration errors detected. Error messages:"
        Hekenga.log(general_errs.pluck(:message).uniq.map {|x| "- #{x}"}.join("\n"))
        Hekenga.log "To get a list:"
        Hekenga.log "Hekenga::Failure::Error.lookup('#{log_id}', #{idx})"
        # TODO - recover message
      end
    end
    def launch_task(task, idx, scope = nil)
      Hekenga.log "Launching task##{idx}: #{task.description}"
      @active_thread = Thread.new do
        @migration.perform_task!(idx, scope)
      end.tap {|t| t.abort_on_exception = true }
    end
    def report_while_active(task, idx)
      # Wait for the log to be generated
      until (@migration.log(idx) rescue nil)
        sleep 1
      end
      # Periodically report on thread progress
      until @migration.log(idx).reload.done
        @active_thread.join unless @active_thread.alive?
        report_status(task, idx)
        return if @migration.log(idx).cancel
        sleep Hekenga.config.report_sleep
      end
      report_status(task, idx)
      return if @migration.log(idx).cancel
      report_errors(idx)
      Hekenga.log "Completed"
    end
    def report_status(task, idx)
      # Simple tasks
      case task
      when Hekenga::DocumentTask
        scope          = @migration.log(idx).failures
        skipped_ctr    = @migration.log(idx).skipped
        valid_errs     = scope.where(_type: "Hekenga::Failure::Validation")
        valid_errs_ctr = valid_errs.count
        Hekenga.log "Processed #{@migration.log(idx).processed} of #{@migration.log(idx).total} (#{valid_errs_ctr} invalid, #{skipped_ctr} skipped)"
      when Hekenga::SimpleTask
        Hekenga.log "Waiting on task"
      end
    end
    def cleanup
      @active_thread = nil
    end

    def continue_prompt?(str)
      loop do
        print "#{str} Continue? (Y/N)\n"
        case gets.chomp.downcase
        when "y"
          return true
        when "n"
          return false
        end
      end
    end
  end
end
