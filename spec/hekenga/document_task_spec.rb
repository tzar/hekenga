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
      expect(migration).to(receive(:write_result!) do |_klass, records|
        expect(records.length).to eq(1) # Rest are skipped
      end)
      migration.perform!
    end

    it "doesn't skip when always_write! is enabled" do
      migration.tasks[0].always_write = true
      expect(migration).to(receive(:write_result!) do |_klass, records|
        expect(records.length).to eq(3)
      end)
      migration.perform!
    end
  end

  describe "transactions" do
    describe "failure during the migration" do
      let(:migration) do
        Hekenga.migration do
          description "Transactions"
          created "2023-04-18 12:25"

          per_document "Demo" do
            scope Example.all
            use_transaction!

            up do |doc|
              Example.all.inc(num: 1)
              raise "error" # to abort the transaction
            end
          end
        end
      end

      it "doesn't commit the transaction" do
        migration.perform!
        expect(Example.all.pluck(:num)).to eq([0, 1, 2])
      end
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
end
