class Example
  include Mongoid::Document

  field :string, default: "blah"
  field :num,    default: 42
  field :date

  validate do
    errors.add(:num, "Can't be 100") if num == 100
  end
end
