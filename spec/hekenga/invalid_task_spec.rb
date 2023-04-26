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
      records = migration.task_records(0)
      doc = Example.find_by(num: 2)
      expect(records.where(ids: doc.id).first.invalid_ids).to include(doc.id)
    end
  end

  describe "invalid strategies" do
    let(:migration) do
      Hekenga.migration do
        description "Broken"
        created "2017-04-04 12:00"
        batch_size 1
        per_document "break" do
          scope Example.all
          up do |doc|
            doc.num = 100 if doc.num == 2
          end
        end
        task "chain" do
          up {}
        end
      end
    end

    it "has a default strategy of :continue" do
      expect(migration.tasks[0].invalid_strategy).to eq(:continue)
    end
  end
end
