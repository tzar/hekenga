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
      process = Hekenga::MasterProcess.new(migration)
      stats = process.send(:combined_stats, 0)
      log = Hekenga::Log.last
      expect(log.done).to eq(true)
      expect(stats).to eq("failed" => 0, "invalid" => 0, "written" => 1)
    end

    context "test mode" do
      it "should not persist" do
        migration.test_mode!
        migration.perform!
        expect(Example.asc(:_id).pluck(:num)).to eq([0, 1, 2])
      end
    end

    context "timeless mode" do
      it "should not update timestamps" do
        expect do
          migration.tasks[0].timeless = true
          migration.perform!
        end.to_not(change { Example.asc(:_id).pluck(:updated_at) })
      end
    end
  end

  describe "skipping unchanged records" do
    let(:migration) do
      Hekenga.migration do
        description "Skipping unchanged records"
        created "2023-04-17 15:11"

        per_document "Demo" do
          scope Example.all
          up do |doc|
            next unless doc.num == 1
            doc.num += 1
          end
        end
      end
    end

    it "skips un-needed writes" do
      expect_any_instance_of(Hekenga::DocumentTaskExecutor).to(receive(:bulk_write) do |instance, operations, **kwargs|
        expect(operations.length).to eq(1) # Rest are skipped
        expect(operations.map(&:keys).flatten.uniq).to eq(%i[replace_one])
      end)
      migration.perform!
    end

    it "doesn't skip when always_write! is enabled" do
      migration.tasks[0].always_write = true
      expect_any_instance_of(Hekenga::DocumentTaskExecutor).to(receive(:bulk_write) do |instance, operations, **kwargs|
        expect(operations.length).to eq(3) # Rest are skipped
        expect(operations.map(&:keys).flatten.uniq).to eq(%i[replace_one])
      end)
      migration.perform!
    end
  end

  describe "callbacks" do
    let(:migration) do
      Hekenga.migration do
        description "callbacks"
        created "2023-04-27 15:47"

        per_document "Demo" do
          scope Example.all
          up do |doc|
            doc.num += 1
          end
        end
      end
    end

    it "runs callbacks" do
      migration.perform!

      expect(Example.all.pluck(:num_copy)).to eq(Example.all.pluck(:num))
    end

    it "doesn't run callbacks when skip_prepare" do
      migration.tasks[0].skip_prepare = true
      migration.perform!
      expect(Example.all.pluck(:num_copy)).to_not eq(Example.all.pluck(:num))
    end
  end


  describe "transactions" do
    let(:migration) do
      Hekenga.migration do
        description "Transactions"
        created "2023-04-18 12:25"

        per_document "Demo" do
          scope Example.all
          use_transaction!

          up do |doc|
            Example.all.inc(num: 1)
          end
        end
      end
    end

    it "runs" do
      migration.perform!
      expect(Example.all.pluck(:num)).to eq([3, 4, 5])
    end
  end

  context "delete_then_insert records mode" do
    describe "single task up block" do
      let(:migration) do
        Hekenga.migration do
          description "Simple per_doc test"
          created "2017-03-30 14:30"

          per_document "Demo" do
            scope Example.gt(num: 0)
            write_strategy :delete_then_insert
            always_write!

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
        process = Hekenga::MasterProcess.new(migration)
        stats = process.send(:combined_stats, 0)
        log = Hekenga::Log.last
        expect(log.done).to eq(true)
        expect(stats).to eq("failed" => 0, "invalid" => 0, "written" => 1)
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
end
