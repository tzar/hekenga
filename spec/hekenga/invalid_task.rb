require 'spec_helper'

describe "Tasks with invalid result" do
  before(:each) do
    3.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
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
            doc.num = 100 if doc.num == 2
          end
        end
      end
    end

    it "should log correctly without crashing" do
      expect { migration.perform!  }.to_not raise_error
      log = migration.log(0)

      expect(log.error).to eq(true)
      expect(log.cancel).to eq(false)
      expect(log.failures.count).to eq(1)

      failure = log.failures.last
      doc     = Example.find_by(num: 2)
      expect(failure.class).to eq(Hekenga::Failure::Validation)
      expect(failure.pkey).to eq(migration.to_key)
      expect(failure.task_idx).to eq(0)
      expect(failure.document["num"]).to eq(100)
      expect(failure.doc_id).to eq(doc.id)
      expect(failure.errs).to eq(["Num Can't be 100"])
    end
  end
end
