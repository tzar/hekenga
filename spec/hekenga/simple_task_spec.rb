require 'spec_helper'

describe Hekenga::SimpleTask do
  before(:each) do
    3.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
    end
  end
  describe "double task with up block" do
    let(:migration) do
      Hekenga.migration do
        description "The simplest of tasks"
        created "2017-03-30 14:30"

        task "Demo up" do
          up do
            Example.all.set num: 42 if actual?
          end
        end
        task "Chained up" do
          up do
            Example.all.inc(num: 1) unless test?
          end
        end
      end
    end

    it "should carry out the migration" do
      migration.perform!
      expect(Example.pluck(:num)).to eq([43, 43, 43])
    end
    
    context "test mode" do
      before { migration.test_mode! }

      it "should not run due to internal conditionals" do
        migration.perform!
        expect(Example.pluck(:num)).to eq([0, 1, 2])
      end
    end
  end
end
