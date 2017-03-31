$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'active_record'
# ActiveSupport::Deprecation.debug = true
require 'action_view'
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ":memory:")
require 'draft_punk'
require 'dummy_app/db_schema.rb'
require 'dummy_app/models'

def setup_model_approvals
  House.disable_approval!
  Room.disable_approval!
  House.requires_approval nullify: House::NULLIFY_ATTRIBUTES
end

def disable_all_approvals
  House.disable_approval!
  Room.disable_approval!
  Permit.disable_approval!
  Closet.disable_approval!
  TrimStyle.disable_approval!
end

def setup_house_with_draft
  House.delete_all
  Room.delete_all
  Closet.delete_all
  ElectricalOutlet.delete_all
  Permit.delete_all
  @house = House.new(architectual_style: 'Ranch')

  room = Room.new(name: 'Living Room')
  room.custom_flooring_style = CustomFlooringStyle.new(name: 'hardwood')
  room.electrical_outlets << ElectricalOutlet.new(outlet_count: 4)
  room.electrical_outlets << ElectricalOutlet.new(outlet_count: 2)
  room.closets << Closet.new(style: 'wall')
  room.closets << Closet.new(style: 'walk-in')
  room.trim_styles << TrimStyle.new(style: 'crown')

  @house.rooms   << room
  @house.rooms   << Room.new(name: 'Entryway')
  @house.permits << Permit.new(permit_type: 'Construction')
  @house.save!

  @draft = @house.editable_version
end

def setup_draft_with_changes
  @draft.architectual_style = "Victorian"

  @draft_room = @draft.rooms.first
  @draft_room.name = 'Parlor'
  @draft_room.custom_flooring_style.update_column(:name, 'shag')

  closet = @draft_room.closets.where(style: 'wall').first
  closet.style='hidden'
  closet.save!

  @draft_room.closets << Closet.create(style: 'coat')

  @draft_room.closets.delete(@draft_room.closets.where(style: 'walk-in'))
  @draft_room.save!

  @draft.save!
  @draft = House.unscoped.find @draft.id
end

def set_house_architectual_style_to_lodge
  self.architectual_style = 'Lodge'
end
