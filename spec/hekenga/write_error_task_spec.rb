require 'spec_helper'

describe "Tasks with write errors" do
  before(:each) do
    3.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
    end
  end

  describe "doc task that does nothing" do
    let(:migration) do
      Hekenga.migration do
        description "Broken"
        created "2017-03-31 17:00"
        batch_size 3

        per_document "nothing" do
          scope Example.all
          always_write!
          write_strategy :delete_then_insert
          up do |doc|
            # NOOP
          end
        end
      end
    end

    before do
      expect_any_instance_of(Hekenga::DocumentTaskExecutor).to(receive(:bulk_write) do |instance, operations, **kwargs|
        raise Mongo::Error::BulkWriteError, {}
      end)
    end

    it "should log correctly without crashing" do
      documents = Example.asc(:_id).all.map(&:as_document)
      expect { migration.perform!  }.to_not raise_error
      log = migration.log(0)

      expect(log.error).to eq(true)
      expect(log.failures.count).to eq(1)

      failure = log.failures.last
      expect(failure.class).to eq(Hekenga::Failure::Write)
      expect(failure.pkey).to eq(migration.to_key)
      expect(failure.task_idx).to eq(0)
      expect(failure.documents).to eq(documents)
    end
  end

  describe "transactional task" do
    let(:migration) do
      Hekenga.migration do
        description "Broken"
        created "2017-03-31 17:00"
        batch_size 3

        per_document "nothing" do
          scope Example.all
          always_write!
          use_transaction!
          up do |doc|
            # NOOP
          end
        end
      end
    end

    before do
      expect_any_instance_of(Hekenga::DocumentTaskExecutor).to(receive(:bulk_write) do |instance, operations, **kwargs|
        raise Mongo::Error::BulkWriteError, {}
      end)
    end

    it "should crash so the job can retry" do
      expect { migration.perform!  }.to raise_error(Mongo::Error::BulkWriteError)
      log = migration.log(0)

      expect(log.error).to eq(false)
      expect(log.cancel).to eq(false)
      expect(log.failures.count).to eq(0)
    end
  end
end
