module Hekenga
  class Migration
    attr_accessor :stamp, :description
    attr_reader :tasks

    def initialize
      @tasks = []
    end

    def timestamp
      self.stamp.strftime("%Y-%m-%dT%H:%M")
    end

    def desc_to_token
      @desc_to_token ||= self.description.gsub(/[^A-Za-z]+/,"_").gsub(/(^_|_$)/,"")
    end

    def inspect
      "<Hekenga::Migration #{self.to_key}>"
    end

    def to_key
      @pkey ||= "#{timestamp}-#{desc_to_token}"
    end

    def log
      @log ||= Hekenga::Log.where(pkey: self.to_key).first
    end

    def performed?
      !!log
    end

    def validate!
      # TODO
      # - check stamp is date
      # - check description is present and desc_to_token has length
      # - check at least one task
    end
  end
end
