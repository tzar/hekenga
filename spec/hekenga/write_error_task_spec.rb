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
          up do |doc|
            # NOOP
          end
        end
      end
    end

    before do
      expect(migration).to receive(:write_records!) do
        raise "Write error"
      end
    end

    it "should log correctly without crashing" do
      documents = Example.asc(:_id).all.map(&:as_document)
      expect { migration.perform!  }.to_not raise_error
      log = migration.log(0)

      expect(log.error).to eq(true)
      expect(log.cancel).to eq(true)
      expect(log.failures.count).to eq(1)

      failure = log.failures.last
      expect(failure.class).to eq(Hekenga::Failure::Write)
      expect(failure.pkey).to eq(migration.to_key)
      expect(failure.task_idx).to eq(0)
      expect(failure.documents).to eq(documents)
      expect(failure.message).to eq("Write error")

      expect(Example.count).to eq(0)
    end
  end
end
