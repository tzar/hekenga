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
          print "TERMINATING DUE TO ERRORS\n"
          return
        end
        cleanup
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
        report_status(task, idx)
        sleep Hekenga.config.report_sleep
      end
      # TODO - final status report
      report_status(task, idx)
      print "Completed\n"
    end
    def report_status(task, idx)
      # Simple tasks
      case task
      when Hekenga::DocumentTask
        print "Processed #{@migration.log(idx).processed} of #{@migration.log(idx).total}\n"
        # TODO - report errors, skipped, validation
      when Hekenga::SimpleTask
        print "Waiting on task\n"
      end
    end
    def cleanup
      @active_thread = nil
    end
  end
end
