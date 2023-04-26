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

        per_document do
          scope Example.all
          batch_size 1
          up do |doc|
            # General error
            if doc.num == 1
              raise "fail"
            end
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
      original_write = Hekenga::DocumentTaskExecutor.instance_method(:bulk_write)
      allow_any_instance_of(Hekenga::DocumentTaskExecutor).to receive(:bulk_write) do |instance, operations, **kwargs|
        raise Mongo::Error::BulkWriteError, {} if break_on_write
        original_write.bind_call(instance, operations, **kwargs)
      end
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
      expect(Example.pluck(:num).sort).to eq([10, 11, 12])
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
      original_write = Hekenga::DocumentTaskExecutor.instance_method(:bulk_write)
      allow_any_instance_of(Hekenga::DocumentTaskExecutor).to receive(:bulk_write) do |instance, operations, **kwargs|
        raise Mongo::Error::BulkWriteError, {} if break_on_write
        original_write.bind_call(instance, operations, **kwargs)
      end

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
  describe "chained simple migrations" do
    let(:migration) do
      Hekenga.migration do
        description "errored migration"
        created "2017-03-31 17:00"
        batch_size 3

        task "stage1" do
          up do
            raise "fail" if Example.where(num: 0).any?
            Example.all.inc(num: 1)
          end
        end
        task "stage2" do
          up do
            raise "fail" if Example.where(num: 2).any?
            Example.all.inc(num: 1)
          end
        end
      end
    end
    before do
      migration.perform!
    end
    it "should perform stage 2 when recovering from stage 1" do
      Example.where(num: 0).update_all(num: 3)
      expect(migration.recover!).to eq(false)
      expect(Example.pluck(:num).sort).to eq([2, 3, 4])
    end
    it "should allow double recovery" do
      Example.where(num: 0).update_all(num: 3)
      expect(migration.recover!).to eq(false)
      Example.where(num: 2).update_all(num: 5)
      expect(migration.recover!).to eq(true)
      expect(Example.pluck(:num).sort).to eq([4, 5, 6])
    end
  end
  describe "validation error in early stage" do
    let(:migration) do
      Hekenga.migration do
        description "invalid migration"
        created "2017-04-05 17:00"
        batch_size 3

        per_document "stage1" do
          scope Example.all
          when_invalid :continue
          up do |doc|
            if doc.num.zero?
              puts "Setting doc.num(#{doc.num}) to 100"
              doc.num = 100
            else
              puts "Setting doc.num(#{doc.num}) to #{doc.num + 1}"
              doc.num += 1
            end
          end
        end
        per_document "stage2" do
          scope Example.all
          when_invalid :continue
          up do |doc|
            if doc.string == "blah"
              doc.string = "uhoh"
            else
              doc.string = "blah"
            end
          end
        end
      end
    end

    before do
      migration.perform!
    end

    it "should perform both stages" do
      expect(Example.pluck(:string)).to eq(["blah"]*3)
      expect(Example.pluck(:num).sort).to eq([0,2,3])
    end

    it "should re-run stage1 but not stage2" do
      Example.where(num: 0).update_all(num: 3)
      expect(migration.recover!).to eq(true)
      expect(Example.pluck(:num).sort).to eq([2,3,4])
      expect(Example.pluck(:string)).to eq(["blah"]*3)
    end
  end
end
