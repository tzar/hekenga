require 'spec_helper'

describe Hekenga::DocumentTask do
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

        per_document "Demo" do
          scope Example.gt(num: 0)

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

    it "should carry out the migration" do
      migration.perform!
      expect(Example.asc(:_id).pluck(:num)).to eq([0, 1, 3])
    end
    it "should log correctly" do
      migration.perform!
      log = Hekenga::Log.last
      expect(log.total).to eq(2)
      expect(log.processed).to eq(2)
      expect(log.done).to eq(true)
      expect(log.skipped).to eq(1)
    end
    context "test mode" do
      it "should not persist" do
        migration.test_mode!
        migration.perform!
        expect(Example.asc(:_id).pluck(:num)).to eq([0, 1, 2])
      end
    end
  end
end
