require 'spec_helper'

describe "Hekenga::DocumentTask (parallel)", type: :job do
  include ActiveJob::TestHelper
  before do
    clear_enqueued_jobs
    clear_performed_jobs
  end
  before(:each) do
    3.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
    end
  end
  describe "single task up block" do
    let(:migration) do
      Hekenga.migration do
        description "Simple per_doc test"
        created "2017-03-30 14:30"
        batch_size 1

        per_document "Demo" do
          scope Example.gt(num: 0)
          parallel!

          setup do
            @increment = 1
          end

          filter do |doc|
            doc.num > 1
          end

          up do |doc|
            doc.num += @increment
          end
        end
      end
    end

    it "should queue the jobs" do
      expect {
        migration.perform_task!(0)
      }.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(2)
    end
    it "should carry out the migration" do
      perform_enqueued_jobs do
        migration.perform!
      end
      expect(Example.asc(:_id).pluck(:num)).to eq([0, 1, 3])
    end
    context "in transaction mode" do
      before { migration.tasks[0].use_transaction = true }

      it "should carry out the migration" do
        perform_enqueued_jobs do
          migration.perform!
        end
        expect(Example.asc(:_id).pluck(:num)).to eq([0, 1, 3])
      end
    end
    it "should log correctly" do
      perform_enqueued_jobs do
        migration.perform!
      end
      log = Hekenga::Log.last
      expect(log.total).to eq(2)
      expect(log.processed).to eq(2)
      expect(log.done).to eq(true)
      expect(log.skipped).to eq(1)
    end
    context "test mode" do
      it "should not persist" do
        perform_enqueued_jobs do
          migration.test_mode!
          migration.perform!
        end
        expect(Example.asc(:_id).pluck(:num)).to eq([0, 1, 2])
      end
    end
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end
end
