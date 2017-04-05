require 'spec_helper'

describe "Hekenga#recover!" do
  include ActiveJob::TestHelper
  before(:each) do
    3.times.each do |idx|
      Example.create! string: "idx-#{idx}", num: idx
    end
  end
  describe "simple migrations" do
    let(:migration) do
      Hekenga.migration do
        description "errored migration"
        created "2017-03-31 17:00"
        batch_size 3

        task do
          up do
            raise "fail" if Example.where(num: 0).any?
            Example.all.inc(num: 1)
          end
        end
      end
    end
    before do
      migration.perform!
      allow(migration).to receive(:prompt).and_return(true)
    end
    it "should return false if it fails again" do
      expect(Example.pluck(:num).sort).to eq([0,1,2])
      expect(migration.recover!).to eq(false)
      expect(Example.pluck(:num).sort).to eq([0,1,2])
    end
    it "should recover when fixed" do
      Example.all.inc(num: 1)
      expect(migration.recover!).to eq(true)
      expect(Example.pluck(:num).sort).to eq([2,3,4])
    end
  end
  describe "document migrations" do
    let(:migration) do
      Hekenga.migration do
        description "error mix"
        created "2017-03-31 17:00"
        batch_size 1

        per_document do
          scope Example.all
          up do |doc|
            # General error
            raise "fail" if doc.num == 1
            if doc.num == 2
              # Validation error
              doc.num = 100
            else
              # Actual migration
              doc.num += 5
            end
          end
        end
      end
    end
    break_on_write = true
    before do
      # Write error
      allow(migration).to receive(:write_records!) do |klass, records|
        raise "fail" if break_on_write
        klass.collection.insert_many(records.map(&:as_document))
      end
      allow(migration).to receive(:prompt).and_return(true)
      migration.perform!
    end
    it "should return false if it fails again" do
      expect(migration.recover!).to eq(false)
    end
    it "should recover when fixed" do
      break_on_write = false
      Example.all.inc(num: 5)
      expect(migration.recover!).to eq(true)
      expect(Example.count).to eq(3)
      # 5 because the cached record that gets written back doesn't get inc'd
      expect(Example.pluck(:num).sort).to eq([5, 11, 12])
    end
    it "should recover when failed again then fixed" do
      break_on_write = false
      expect(migration.recover!).to eq(false)
      expect(Example.count).to eq(3)
      Example.all.inc(num: 5)
      expect(migration.recover!).to eq(true)
      expect(Example.pluck(:num).sort).to eq([10, 11, 12])
    end
  end
  describe "parallel migrations" do
    let(:migration) do
      Hekenga.migration do
        description "error mix"
        created "2017-03-31 17:00"
        batch_size 1

        per_document do
          scope Example.all
          parallel!
          up do |doc|
            # General error
            raise "fail" if doc.num == 1
            if doc.num == 2
              # Validation error
              doc.num = 100
            else
              # Actual migration
              doc.num += 5
            end
          end
        end
      end
    end
    break_on_write = true
    before do
      # Write error
      allow(migration).to receive(:write_records!) do |klass, records|
        raise "fail" if break_on_write
        klass.collection.insert_many(records.map(&:as_document))
      end
      allow(migration).to receive(:prompt).and_return(true)
      perform_enqueued_jobs { migration.perform! }
    end
    it "should return false if it fails again" do
      perform_enqueued_jobs do
        expect(migration.recover!).to eq(false)
      end
    end
    it "should recover when fixed" do
      break_on_write = false
      Example.in(num: [1, 2]).inc(num: 5)
      perform_enqueued_jobs do
        expect(migration.recover!).to eq(true)
      end
      expect(Example.count).to eq(3)
      # 5 - the write failure
      # 11, 12 - inc(5), migrated with another inc(5)
      expect(Example.pluck(:num).sort).to eq([5, 11, 12])
    end
    it "should recover when failed again then fixed" do
      break_on_write = false
      perform_enqueued_jobs do
        expect(migration.recover!).to eq(false)
      end
      expect(Example.count).to eq(3)
      Example.all.inc(num: 5)
      perform_enqueued_jobs do
        expect(migration.recover!).to eq(true)
      end
      # 0,1,2, inc(5), migrated with another inc(5)
      expect(Example.pluck(:num).sort).to eq([10, 11, 12])
    end
  end
  describe "chained migrations" do
    # TODO
  end
end
