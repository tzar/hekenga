module Hekenga
  class MasterProcess
    def initialize(migration)
      @migration = migration
    end

    def run!
      puts "Launching migration #{@migration.to_key}"
      @migration.tasks.each.with_index do |task, idx|
        launch_task(task, idx)
        report_while_active(task, idx)
        if @migration.log(idx).cancel
          print "TERMINATING DUE TO CRITICAL ERRORS\n"
          report_errors(idx)
          return
        end
        cleanup
      end
    end
    def report_errors(idx)
      scope  = @migration.log(idx).failures
      log_id = @migration.log(idx).id
      # Validation errors
      valid_errs     = scope.where(_type: "Hekenga::Failure::Validation")
      valid_errs_ctr = valid_errs.count
      unless valid_errs_ctr.zero?
        print "#{valid_errs_ctr} records failed validation. To get a list:\n"
        print "Hekenga::Failure::Validation.lookup('#{log_id}', #{idx})\n"
      end
      # Write failures
      write_errs     = scope.where(_type: "Hekenga::Failure::Write")
      write_errs_ctr = write_errs.count
      unless write_errs_ctr.zero?
        print "#{write_errs_ctr} write errors detected. Error messages:\n"
        print(write_errs.pluck(:message).uniq.map {|x| "- #{x}"}.join("\n")+"\n")
        print "To get a list:\n"
        print "Hekenga::Failure::Write.lookup('#{log_id}', #{idx})\n"
        # TODO - recover message
      end
      # Migration errors
      general_errs     = scope.where(_type: "Hekenga::Failure::Error")
      general_errs_ctr = general_errs.count
      unless general_errs_ctr.zero?
        print "#{general_errs_ctr} migration errors detected. Error messages:\n"
        print(general_errs.pluck(:message).uniq.map {|x| "- #{x}"}.join("\n")+"\n")
        print "To get a list:\n"
        print "Hekenga::Failure::Error.lookup('#{log_id}', #{idx})\n"
        # TODO - recover message
      end
    end
    def launch_task(task, idx)
      puts "Launching task##{idx}: #{task.description}"
      @active_thread = Thread.new do
        @migration.perform_task!(idx)
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
        sleep Hekenga.config.report_sleep
      end
      report_status(task, idx)
      report_errors(idx)
      print "Completed\n"
    end
    def report_status(task, idx)
      # Simple tasks
      case task
      when Hekenga::DocumentTask
        scope          = @migration.log(idx).failures
        skipped_ctr    = @migration.log(idx).skipped
        valid_errs     = scope.where(_type: "Hekenga::Failure::Validation")
        valid_errs_ctr = valid_errs.count
        print "Processed #{@migration.log(idx).processed} of #{@migration.log(idx).total} (#{valid_errs_ctr} invalid, #{skipped_ctr} skipped)\n"
      when Hekenga::SimpleTask
        print "Waiting on task\n"
      end
    end
    def cleanup
      @active_thread = nil
    end
  end
end
