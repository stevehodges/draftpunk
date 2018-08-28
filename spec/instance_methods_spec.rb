require 'spec_helper'

describe DraftPunk::Model::ActiveRecordInstanceMethods do
  before(:all) { setup_model_approvals }
  before do
    setup_house_with_draft
    @draft_room = @draft.rooms.where(name: 'Living Room').first
    @live_room  = @house.rooms.where(name: 'Living Room').first
  end

  context '#get_approved_version' do
    it 'returns the approved version of an object' do
      expect(@house.get_approved_version).to eq @house
      expect(@draft.get_approved_version).to eq @house
    end
  end

  context '#editable_version' do
    it 'returns the draft version of an object if it exists' do
      expect(@house.editable_version).to eq @draft
      expect(@draft.editable_version).to eq @draft

      expect(@live_room.editable_version ).to eq @draft_room
      expect(@draft_room.editable_version).to eq @draft_room

      closet = @live_room.closets.first
      closet_draft = closet.editable_version
      expect(closet_draft).to be_present
      expect(closet_draft.editable_version).to eq closet_draft
    end
    it "builds and returns draft version of an object if it doesn't yet exist" do
      h = House.create
      expect{ h.editable_version }.to     change{ House.count }.by(1)
      expect{ h.editable_version }.to_not change{ House.count }
    end
    it "clones has_one associations" do
      original_flooring_style = @house.rooms.where(name: 'Living Room').first.custom_flooring_style
      draft_flooring_style    = @draft.rooms.where(name: 'Living Room').first.custom_flooring_style
      expect(original_flooring_style.id           ).to_not eq draft_flooring_style.id
      expect(draft_flooring_style.approved_version).to     eq original_flooring_style
    end
    it 'assigns the approved version to drafts with the approved_version_id column' do
      expect(@draft.approved_version_id).to be_present
      expect(@draft.approved_version.id).to eq @draft.approved_version_id
    end
  end

  context :associations do
    it 'finds the live/approved version of the object via the approved_version association' do
      expect(@draft.approved_version).to eq @house
      expect(@house.approved_version).to be_nil

      expect(@draft_room.approved_version).to eq @live_room
      expect(@live_room.approved_version ).to be_nil
    end
    it 'finds the draft version of the object via the draft association' do
      expect(@house.draft).to eq @draft
      expect(@draft.draft).to be_nil

      expect(@draft_room.draft).to be_nil
      expect(@live_room.draft ).to eq @draft_room
    end
  end

  context :interrogators do
    context '#is_draft?' do
      it 'true if the object is the draft version' do
        expect(@draft.is_draft?     ).to be true
        expect(@draft_room.is_draft?).to be true
      end

      it 'false if the object is the live/approved version' do
        expect(@house.is_draft?).to be false
        expect(@live_room.is_draft?).to be false
      end
    end

    context '#has_draft?' do
      it 'false if the object is the draft version' do
        expect(@draft.has_draft?     ).to be false
        expect(@draft_room.has_draft?).to be false
      end

      it 'true if the object is the live/approved version and has a draft' do
        expect(@house.has_draft?    ).to be true
        expect(@live_room.has_draft?).to be true
      end
    end

    it "interrogators raise an error if the model doesn't have an approved_version_id" do
      trim_style = @draft_room.trim_styles.first
      expect { trim_style.has_draft? }.to raise_error(DraftPunk::ApprovedVersionIdError)
      expect { trim_style.is_draft?  }.to raise_error(DraftPunk::ApprovedVersionIdError)
    end
  end

  context :publish_draft do
    before { setup_draft_with_changes }

    it 'the test is set up correctly' do
      expect(@draft.rooms.pluck(:name)).to eq %w(Parlor Entryway)
      room = @draft.rooms.first
      expect(room.closets.count).to be(2)
      expect(room.closets.pluck(:style)).to eq %w(hidden coat)
    end

    it "doesn't change the live/approved version when the draft is changed" do
      h = House.find @house.id
      expect(h).to eq @house
      expect(h.architectual_style).to eq 'Ranch'
      expect(h.rooms.count).to be(2)
      expect(h.rooms.pluck(:name).sort).to eq ['Entryway', 'Living Room']
      expect(h.permits.count).to be(1)
    end

    it "updates the approved object with the draft object's attributes and associations" do
      expect(@house.architectual_style).to eq "Ranch"
      expect(@house.rooms.first.closets.count).to be(2)
      expect(@house.rooms.first.closets.pluck(:style)).to eq %w(wall walk-in)
      @house = House.find @house.id
      @house.publish_draft!
      house = House.find @house.id
      expect(house.architectual_style).to eq @draft.architectual_style
      room = house.rooms.first
      expect(room.closets.count).to be(2)
      expect(room.closets.pluck(:style)).to eq %w(hidden coat)
      expect(room.custom_flooring_style.name).to eq 'shag'
    end

    it "deletes the draft object after publishing" do
      expect{ @house.publish_draft! }.to change{ House.draft.count }.by(-1)
      house = House.find @house.id
      expect(house.draft).to be_nil
    end
  end

  context '#draft_diff' do
    before { setup_draft_with_changes }

    it 'returns attributes which have changed in the draft' do
      diff = @house.draft_diff
      expect(diff.except("id")).to eq({
        "architectual_style"=>{:live=>"Ranch", :draft=>"Victorian"},
        :draft_status=>:changed,
        :class_info=>{:table_name=>"houses", :class_name=>"House"}
      })
    end

    it 'returns associations which have changed in the draft with include_associations option' do
      diff = @house.draft_diff(include_associations: true, include_all_attributes: true)
      expected_house_keys = House.draft_target_associations + @house.send(:diff_relevant_attributes) + [:draft_status, :class_info]

      expect(diff.keys.map(&:to_sym).sort).to eq expected_house_keys.map(&:to_sym).sort
      expect(diff[:rooms].count).to eq @draft.rooms.count

      room_diff = diff[:rooms].select{|room| room["id"][:draft] == @draft_room.id }.first
      approved_room = @draft_room.approved_version
      expect(room_diff["name"]).to eq({live: approved_room.name, draft: @draft_room.name })
    end    

    it 'properly shows attributes which have changed or not changed if include_all_attributes argument is true' do
      diff = @house.draft_diff(include_associations: true, include_all_attributes: true)
      room_diff = diff[:rooms].select{|room| room["id"][:draft] == @draft_room.id }.first
      approved_room = @draft_room.approved_version
      expect(room_diff['name'] ).to eq({live: approved_room.name,  draft: @draft_room.name })
      expect(room_diff['width']).to eq({live: approved_room.width, draft: @draft_room.width })
      expect(room_diff['id']   ).to eq({live: approved_room.id,    draft: @draft_room.id })
    end

    it 'properly sets the draft_status of changed objects' do
      diff = @house.draft_diff(include_associations: true)
      expect(diff[:draft_status]).to eq :changed

      room_diff = diff[:rooms].find{|room| room["id"][:draft] == @draft_room.id }
      expect(room_diff[:draft_status]).to eq :changed
    end

    it 'includes items created in the draft (not associated with the approved version)' do
      diff = @house.draft_diff(include_associations: true, include_all_attributes: true)
      room_diff = diff[:rooms].select{|room| room["id"][:draft] == @draft_room.id }.first
      # The room has a new and a deleted closet, from setup_draft_with_changes
      closets = room_diff[:closets]
      expect(closets.find{|c| c["style"][:live] == "walk-in"}[:draft_status]).to eq :deleted
      expect(closets.find{|c| c["style"][:live] == "coat"}[:draft_status]).to    eq :added
      expect(closets.find{|c| c["style"][:live] == "wall"}[:draft_status]).to    eq :changed
    end

  end

  context '#after_create_draft' do
    before do
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
