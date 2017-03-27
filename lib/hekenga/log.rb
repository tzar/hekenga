module Hekenga
  class Log
    include Mongoid::Document

    field :pkey
    field :desc
    field :stamp

    index({pkey: 1}, unique: true)

    def migration=(migration)
      self.pkey  = migration.to_key
      self.desc  = migration.desc
      self.stamp = migration.stamp
    end
  end
end
