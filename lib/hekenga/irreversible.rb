require 'hekenga/base_error'
module Hekenga
  class Irreversible < Hekenga::BaseError
    def initialize(migration)
      super("#{migration.class.to_s} is not a reversible migration.")
    end
  end
end
