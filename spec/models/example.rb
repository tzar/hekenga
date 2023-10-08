class Example
  include Mongoid::Document
  include Mongoid::Timestamps

  field :string, default: "blah"
  field :num,    default: 42
  field :date
  field :num_copy

  validate do
    errors.add(:num, "Can't be 100") if num == 100
  end

  before_save :test_callback

  def test_callback
    self.num_copy = num
  end
end
