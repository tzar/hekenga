require 'spec_helper'

describe "Watching a migration" do
  before(:each) do
    3.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
    end
  end

  let(:migration) do
    Hekenga.migration do
      description "Watchable migration"
      created "2024-07-02 09:00"

      per_document "Demo" do
        scope Example.all
        up do |doc|
          doc.num += 1
        end
      end
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe "a migration that has not started" do
    it "reports that it hasn't started and returns false" do
      result = nil
      output = capture_stdout do
        result = Hekenga::MasterProcess.new(migration).watch!(interval: 0)
      end
      expect(result).to eq(false)
      expect(output).to include("has not started yet")
    end
  end

  describe "a migration that has completed" do
    before(:each) { migration.perform! }

    it "reports the final result and returns true" do
      result = nil
      output = capture_stdout do
        result = Hekenga::MasterProcess.new(migration).watch!(interval: 0)
      end
      expect(result).to eq(true)
      expect(output).to include("Watching migration #{migration.to_key}")
      expect(output).to include("Migration result:")
      expect(output).to include("Written: 3")
      expect(output).to include("Completed")
    end
  end
end
