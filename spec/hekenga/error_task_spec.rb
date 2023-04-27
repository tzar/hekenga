require 'spec_helper'

describe "Tasks with apply errors" do
  before(:each) do
    3.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
    end
  end

  describe "simple task with error on up" do
    let(:migration) do
      Hekenga.migration do
        description "Broken"
        created "2017-03-31 12:00"
        task "break" do
          up do
            raise "Hell"
          end
        end
      end
    end

    it "should log correctly without crashing" do
      expect { migration.perform!  }.to_not raise_error
      log = migration.log(0)

      expect(log.error).to eq(true)
      expect(log.cancel).to eq(true)
      expect(log.failures.count).to eq(1)

      failure = log.failures.last
      expect(failure.class).to eq(Hekenga::Failure::Error)
      expect(failure.pkey).to eq(migration.to_key)
      expect(failure.task_idx).to eq(0)
      expect(failure.message).to eq("Hell")
      expect(failure.backtrace).to_not eq(nil)
    end
  end

  describe "doc task with error on up" do
    let(:migration) do
      Hekenga.migration do
        description "Broken"
        created "2017-03-31 12:00"
        batch_size 1

        per_document "break" do
          scope Example.all
          up do |doc|
            raise "Problem" if doc.num == 2
          end
        end
      end
    end

    it "should log correctly without crashing" do
      expect { migration.perform!  }.to_not raise_error
      records = migration.task_records(0)
      doc = Example.find_by(num: 2)
      expect(records.where(ids: doc.id).first.failed_ids).to include(doc.id)
    end
  end
end
