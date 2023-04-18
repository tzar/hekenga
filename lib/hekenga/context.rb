module Hekenga
  class Context
    attr_reader :migration
    delegate :session, to: :migration

    def initialize(migration)
      @migration = migration
    end

    def actual?
      !migration.test_mode
    end

    def test?
      !actual?
    end
  end
end
