require 'spec_helper'

describe DraftPunk::Model::ActiveRecordInstanceMethods do
  before(:all)  { setup_model_approvals }
  before(:each) do
    setup_house_with_draft
    @draft_room = @draft.rooms.where(name: 'Living Room').first
    @live_room  = @house.rooms.where(name: 'Living Room').first
  end

  context :get_approved_version do
    it 'returns the approved version of an object' do
      @house.get_approved_version.should == @house
      @draft.get_approved_version.should == @house
    end
  end

  context :editable_version do
    it 'returns the draft version of an object if it exists' do
      @house.editable_version.should == @draft
      @draft.editable_version.should == @draft

      @live_room.editable_version.should == @draft_room
      @draft_room.editable_version.should == @draft_room

      closet = @live_room.closets.first
      closet_draft = closet.editable_version
      closet_draft.should be_present
      closet_draft.editable_version.should == closet_draft
    end
    it "builds and returns draft version of an object if it doesn't yet exist" do
      original_count = House.count
      h = House.create()
      House.count.should == original_count + 1
      h.editable_version
      House.count.should == original_count + 2
      h.editable_version
      House.count.should == original_count + 2
    end
    it "clones has_one associations", focus: true do
      original_flooring_style = @house.rooms.where(name: 'Living Room').first.custom_flooring_style
      draft_flooring_style    = @draft.rooms.where(name: 'Living Room').first.custom_flooring_style
      original_flooring_style.id.should_not == draft_flooring_style.id
      draft_flooring_style.approved_version.should == original_flooring_style
    end
    it 'assigns the approved version to drafts with the approved_version_id column' do
      @draft.approved_version_id.should be_present
      @draft.approved_version
    end
  end

  context :associations do
    it 'finds the live/approved version of the object via the approved_version association' do
      @draft.approved_version.should == @house
      @house.approved_version.should be_nil

      @draft_room.approved_version.should == @live_room
      @live_room.approved_version.should be_nil
    end
    it 'finds the draft version of the object via the draft association' do
      @house.draft.should == @draft
      @draft.draft.should be_nil

      @draft_room.draft.should be_nil
      @live_room.draft.should == @draft_room
    end
  end

  context :interrogators do
    it 'is_draft? returns true if the object is the draft version' do
      @draft.is_draft?.should be_truthy
      @draft_room.is_draft?.should be_truthy
    end

    it 'is_draft? returns false if the object is the live/approved version' do
      @house.is_draft?.should be_falsey
      @live_room.is_draft?.should be_falsey
    end

    it 'has_draft? returns false if the object is the draft version' do
      @draft.has_draft?.should be_falsey
      @draft_room.has_draft?.should be_falsey
    end

    it 'has_draft? returns true if the object is the live/approved version and has a draft' do
      @house.has_draft?.should be_truthy
      @live_room.has_draft?.should be_truthy
    end

    it "interrogators should raise an error if the model doesn't have an approved_version_id" do
      trim_style = @draft_room.trim_styles.first
      expect { trim_style.has_draft? }.to raise_error(DraftPunk::ApprovedVersionIdError)
      expect { trim_style.is_draft? }.to  raise_error(DraftPunk::ApprovedVersionIdError)
    end
  end

  context :publish_draft do
    before(:each) do
      setup_draft_with_changes
    end

    it 'the test is set up correctly' do
      @draft.rooms.pluck(:name) == %w(Parlor)
      room = @draft.rooms.first
      room.closets.count.should be(2)
      room.closets.pluck(:style).should == %w(hidden coat)
    end

    it "doesn't change the live/approved version when the draft is changed" do
      h = House.find @house.id
      h.should == @house
      h.architectual_style.should == 'Ranch'
      h.rooms.count.should be(2)
      h.rooms.pluck(:name).sort.should == ['Entryway', 'Living Room']
      h.permits.count.should be(1)
    end

    it "updates the approved object with the draft object's attributes and associations" do
      @house.architectual_style.should == "Ranch"
      @house.rooms.first.closets.count.should be(2)
      @house.rooms.first.closets.pluck(:style).should == %w(wall walk-in)
      @house = House.find @house.id
      @house.publish_draft!
      house = House.find @house.id
      house.architectual_style.should == @draft.architectual_style
      room = house.rooms.first
      room.closets.count.should be(2)
      room.closets.pluck(:style).should == %w(hidden coat)
      room.custom_flooring_style.name.should == 'shag'
    end

    it "deletes the draft object after publishing" do
      original_count = House.draft.count
      @house.publish_draft!
      house = House.find @house.id
      house.draft.should be_nil
      House.draft.count.should == (original_count - 1)
    end
  end

  context :draft_diff do
    before(:each) do
      setup_draft_with_changes
    end

    it 'returns attributes which have changed in the draft' do
      diff = @house.draft_diff
      diff.except("id").should == {
        "architectual_style"=>{:live=>"Ranch", :draft=>"Victorian"},
        draft_status: :changed
      }
    end

    it 'returns associations which have changed in the draft with include_associations option' do
      diff = @house.draft_diff(include_associations: true, include_all_attributes: true)
      expected_house_keys = House.draft_target_associations + @house.send(:diff_relevant_attributes) + [:draft_status]

      diff.keys.map(&:to_sym).sort.should == expected_house_keys.map(&:to_sym).sort
      diff[:rooms].count.should == @draft.rooms.count

      room_diff = diff[:rooms].select{|room| room["id"][:draft] == @draft_room.id }.first
      approved_room = @draft_room.approved_version
      room_diff["name"].should == {live: approved_room.name, draft: @draft_room.name }
    end    

    it 'should properly show attributes which have changed or not changed if include_all_attributes argument is true' do
      diff = @house.draft_diff(include_associations: true, include_all_attributes: true)
      room_diff = diff[:rooms].select{|room| room["id"][:draft] == @draft_room.id }.first
      approved_room = @draft_room.approved_version
      room_diff["name"].should  == {live: approved_room.name, draft: @draft_room.name }
      room_diff["width"].should == {live: approved_room.width, draft: @draft_room.width }
      room_diff["id"].should    == {live: approved_room.id, draft: @draft_room.id }
    end

    it 'should properly set the draft_status of changed objects' do
      diff = @house.draft_diff(include_associations: true)
      diff[:draft_status].should == :changed

      room_diff = diff[:rooms].find{|room| room["id"][:draft] == @draft_room.id }
      room_diff[:draft_status].should == :changed
    end

    it 'should include items created in the draft (not associated with the approved version)' do
      diff = @house.draft_diff(include_associations: true, include_all_attributes: true)
      room_diff = diff[:rooms].select{|room| room["id"][:draft] == @draft_room.id }.first
      # The room has a new and a deleted closet, from setup_draft_with_changes
      closets = room_diff[:closets]
      closets.find{|c| c["style"][:live] == "walk-in"}[:draft_status].should == :deleted
      closets.find{|c| c["style"][:live] == "coat"}[:draft_status].should    == :added
      closets.find{|c| c["style"][:live] == "wall"}[:draft_status].should    == :changed
    end

  end

  context :after_create_draft do
    before(:each) do
      House.send(:define_method, 'after_create_draft') do
        self.architectual_style = 'Lodge'
        save
      end
      setup_model_approvals
      setup_house_with_draft
    end

    it "modifies the draft object per the after_create_draft when a draft is created" do
      expect(@house.architectual_style).to eq 'Ranch'
      expect(@draft.architectual_style).to eq 'Lodge'
    end
  end
end
