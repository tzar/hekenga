require 'hekenga/irreversible'
require 'hekenga/virtual_method'

module Hekenga
  class Simple
    def up
      throw Hekenga::VirtualMethod.new(self)
    end
    def down
      throw Hekenga::Irreversible.new(self.class, :down)
    end
  end
end
