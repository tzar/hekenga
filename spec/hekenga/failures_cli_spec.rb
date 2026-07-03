require 'spec_helper'

describe "Reporting migration failures" do
  before(:each) do
    5.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
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

  describe "a doc task with an error on up" do
    let(:migration) do
      Hekenga.migration do
        description "Failing report"
        created "2024-07-02 10:00"
        batch_size 1

        per_document "break" do
          scope Example.all
          up do |doc|
            raise "Problem" if doc.num >= 3
          end
        end
      end
    end

    let(:failed_docs) { Example.where(:num.gte => 3).to_a }

    before do
      capture_stdout { migration.perform! }
    end

    it "reports the failed document IDs via #tasks" do
      summaries = Hekenga::FailureReport.new(migration).tasks
      expect(summaries.length).to eq(1)
      expect(summaries.first[:idx]).to eq(0)
      expect(summaries.first[:failed_ids]).to match_array(failed_docs.map(&:id))
      expect(summaries.first[:invalid_ids]).to be_empty
    end

    it "prints the failed document IDs" do
      output = capture_stdout do
        Hekenga::FailureReport.new(migration).print!
      end
      expect(output).to include(migration.to_key)
      expect(output).to include("Failed (#{failed_docs.length})")
      failed_docs.each do |doc|
        expect(output).to include("\"#{doc.id}\"")
      end
    end
  end

  describe "a doc task that produces an invalid document" do
    let(:migration) do
      Hekenga.migration do
        description "Invalid report"
        created "2024-07-02 11:00"
        batch_size 1

        per_document "break" do
          scope Example.all
          up do |doc|
            doc.num = 100 if doc.num >= 3
          end
        end
      end
    end

    let(:invalid_docs) { Example.where(:num.gte => 3).to_a }

    before do
      capture_stdout { migration.perform! }
    end

    it "reports the invalid document IDs" do
      summaries = Hekenga::FailureReport.new(migration).tasks
      expect(summaries.first[:invalid_ids]).to match_array(invalid_docs.map(&:id))

      output = capture_stdout do
        Hekenga::FailureReport.new(migration).print!
      end
      expect(output).to include("Invalid (#{invalid_docs.length})")
      invalid_docs.each do |doc|
        expect(output).to include("\"#{doc.id}\"")
      end
    end
  end

  describe "a clean migration" do
    let(:migration) do
      Hekenga.migration do
        description "Clean report"
        created "2024-07-02 13:00"

        per_document "noop" do
          scope Example.all
          up do |doc|
            doc.num += 1
          end
        end
      end
    end

    before do
      capture_stdout { migration.perform! }
    end

    it "reports that there are no failed or invalid documents" do
      expect(Hekenga::FailureReport.new(migration).tasks).to be_empty

      output = capture_stdout do
        Hekenga::FailureReport.new(migration).print!
      end
      expect(output).to include("No failed or invalid documents.")
    end
  end
end
