class Example
  include Mongoid::Document

  field :string, default: "blah"
  field :num,    default: 42
end
