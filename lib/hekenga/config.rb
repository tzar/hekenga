module Hekenga
  class Config
    attr_accessor :dir, :root
    def initialize
      @root = Dir.pwd
      @dir  = ["db", "hekenga"]
    end
    def abs_dir
      File.join(@root, *[@dir].flatten)
    end
  end
end
