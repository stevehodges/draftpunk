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
	  	@draft.architectual_style = "Victorian"
	  	room = @draft.rooms.first
	  	room.name = 'Parlor'

	  	closet = room.closets.where(style: 'wall').first
	  	closet.style='hidden'
	  	closet.save!

	  	room.closets.delete(room.closets.where(style: 'walk-in'))
	  	room.save!

	  	@draft.save!
	  	@draft = House.find @draft.id
  	end

  	it 'the test is set up correctly' do
  		@draft.rooms.pluck(:name) == %w(Parlor)
  		room = @draft.rooms.first
  		room.closets.count.should be(1)
  		room.closets.pluck(:style).should == %w(hidden)
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
  		@house = House.find @house.id
  		@house.publish_draft!
  		house = House.find @house.id
  		house.architectual_style.should == @draft.architectual_style
  		house.rooms.first.closets.count.should be(1)
  		house.rooms.first.closets.pluck(:style).should == %w(hidden)
	  end

	  it "deletes the draft object after publishing" do
  		original_count = House.draft.count
  		@house.publish_draft!
  		house = House.find @house.id
  		house.draft.should be_nil
  		House.draft.count.should == (original_count - 1)
	  end
  end
end
