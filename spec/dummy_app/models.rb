class House < ActiveRecord::Base
  has_many :rooms
  has_many :permits

  NULLIFY_ATTRIBUTES = %i(address)
  CREATES_NESTED_DRAFTS_FOR = %i(rooms)
end

class Room < ActiveRecord::Base
  belongs_to :house
  has_one    :custom_flooring_style
  has_many   :electrical_outlets
  has_many   :closets
  has_many   :trim_styles

  CREATES_NESTED_DRAFTS_FOR = %i(custom_flooring_style closets trim_styles)
end

class Permit < ActiveRecord::Base
  belongs_to :house
end

class CustomFlooringStyle < ActiveRecord::Base
  belongs_to :room
end

class ElectricalOutlet < ActiveRecord::Base
  belongs_to :room
end

class Closet < ActiveRecord::Base
  belongs_to :room
  attr_accessor :shape
end

class TrimStyle < ActiveRecord::Base
  belongs_to :room
  attr_accessor :style
end

class Apartment < ActiveRecord::Base
end
