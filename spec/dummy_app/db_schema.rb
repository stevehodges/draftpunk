ActiveRecord::Schema.define(:version => 20150615203843) do
  self.verbose = false
  create_table :houses, force: true do |t|
    t.string  :architectual_style,   default: 'Bungalow'
    t.string  :address, default: '1 Maple Ln'
    t.integer :approved_version_id
  end
  create_table :permits, force: true do |t|
    t.string   :permit_type
    t.integer  :house_id
  end
  create_table :custom_flooring_styles, force: true do |t|
    t.string  :name
    t.integer :approved_version_id
    t.integer :room_id
  end
  create_table :rooms, force: true do |t|
    t.integer :house_id
    t.string  :name,     default: 'Living Room'

    t.integer :width,    default: 12
    t.integer :length,   default: 12
    t.integer :height,   default: 8

    t.integer  :approved_version_id
    t.integer  :current_approved_version_id
    t.datetime :created_at
    t.datetime :updated_at
  end
  create_table :electrical_outlets, force: true do |t|
    t.integer :room_id
    t.integer :outlet_count
    t.boolean :grounded,  default: true
  end
  create_table :closets, force: true do |t|
    t.integer :room_id
    t.string  :style,     default: 'walk-in'
    t.integer :approved_version_id
  end
  create_table :trim_styles, force: true do |t|
    t.integer :room_id
    t.string  :style,     default: 'baseboard'
  end
  create_table :apartments, force: true do |t|
    t.string :name
    t.integer :approved_version_id
  end
end