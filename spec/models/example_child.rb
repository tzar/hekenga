class ExampleChild
  include Mongoid::Document

  field :value, default: 0

  belongs_to :example
end
