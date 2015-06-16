$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'active_record'
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
require 'draft_punk'
require 'dummy_app/db_schema.rb'
require 'dummy_app/models'

def setup_model_approvals
  House.disable_approval!
  Room.disable_approval!
  House.requires_approval associations: House::APPROVABLE_ASSOCIATIONS, nullify: House::NULLIFY_ATTRIBUTES
  Room.accepts_nested_drafts_for Room::APPROVABLE_ASSOCIATIONS
end

def setup_house_with_draft
  House.delete_all
  @house = House.new(architectual_style: 'Ranch')

  room = Room.new(name: 'Living Room')
  room.flooring_style      = FlooringStyle.create(name: 'hardwood')
  room.electrical_outlets << ElectricalOutlet.new(outlet_count: 4)
  room.electrical_outlets << ElectricalOutlet.new(outlet_count: 2)
  room.closets << Closet.new(style: 'wall')
  room.closets << Closet.new(style: 'walk-in')
  room.trim_styles << TrimStyle.new(style: 'crown')

  @house.rooms   << room
  @house.rooms   << Room.new(name: 'Entryway')
  @house.permits << Permit.new(permit_type: 'Construction')
  @house.save

  @draft = @house.editable_version
end