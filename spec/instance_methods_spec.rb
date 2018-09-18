require 'spec_helper'
require 'timecop'

describe DraftPunk::Model::ActiveRecordInstanceMethods do
  before(:all) { setup_model_approvals }
  before do
    setup_house_with_draft
    @draft_room = @draft.rooms.where(name: 'Living Room').first
    @live_room  = @house.rooms.where(name: 'Living Room').first
  end

  describe '#get_approved_version' do
    it 'returns the approved version of an object' do
      expect(@house.get_approved_version).to eq @house
      expect(@draft.get_approved_version).to eq @house
    end
  end

  describe '#editable_version' do
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

  describe 'associations' do
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

  describe 'interrogators' do
    describe '#is_draft?' do
      it 'true if the object is the draft version' do
        expect(@draft.is_draft?     ).to be true
        expect(@draft_room.is_draft?).to be true
      end

      it 'false if the object is the live/approved version' do
        expect(@house.is_draft?).to be false
        expect(@live_room.is_draft?).to be false
      end
    end

    describe '#has_draft?' do
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

  describe '#publish_draft!' do
    before { setup_draft_with_changes }
    context 'does not track approved version history' do
      before { allow(Room).to receive(:tracks_approved_version_history?).and_return false }

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

    context 'tracks_approved_version_history' do
      let(:approved_version) { @draft_room.approved_version }

      it { expect(@live_room.tracks_approved_version_history?).to be true }

      it 'creates a duplicate of the approved version to represent the previously-approved version' do
        # ordinarily, the room count is changed by -1 since the draft is deleted. So,
        # we want to see 0 here.
        expect{ approved_version.publish_draft! }.to change{ Room.count }.by(0)
        expect(Room.last.id).to_not eq approved_version.id
      end

      describe 'historic version attributes' do
        it 'attributes match the previously-approved version' do
          previous_attributes = @live_room.attributes.except('created_at', 'updated_at', 'id', 'current_approved_version_id')
          @live_room.publish_draft!
          expect(Room.last.attributes.except('created_at', 'updated_at', 'id', 'current_approved_version_id')).to eq previous_attributes
          expect(Room.last.id).to_not eq @live_room.id
        end

        it 'has the original timestamps' do
          Timecop.freeze 2.days.from_now
          original_created_at = @live_room.created_at
          original_updated_at = @live_room.updated_at
          @live_room.publish_draft!
          expect(@live_room.previous_version.created_at).to eq original_created_at
          expect(@live_room.previous_version.updated_at).to eq original_updated_at
          Timecop.return
        end

        it 'has its associations' do
          @live_room.publish_draft!
          expect(@live_room.previous_version.closets).to be_present
        end
      end

      it 'stores the previously-approved version id' do
        @live_room.publish_draft!
        expect(Room.last.current_approved_version_id).to eq(@live_room.id)
      end

      it 'updates the approved version as expected' do
        @live_room.publish_draft!
        expect(@live_room.reload.name).to eq 'Parlor'
      end

      it 'does not set approved version id for the historic version' do
        @live_room.publish_draft!
        expect(Room.last.approved_version_id).to be_nil
      end
    end
  end

  describe 'version history' do
    it { expect(@live_room.tracks_approved_version_history?).to be true }

    describe '#previous_version' do
      it 'is the most recent version approved' do
        expect(@live_room.name).to eq 'Living Room'
        expect(@live_room.previous_version).to be_blank
        @draft_room.update_attributes name: 'Parlour'

        @live_room.publish_draft!
        expect(@live_room.reload.previous_version.name).to eq 'Living Room'
        expect(@live_room.previous_versions.count).to eq 1

        @live_room.editable_version.update_attributes name: 'Library'
        @live_room.publish_draft!
        expect(@live_room.reload.previous_version.name).to eq 'Parlour'
        expect(@live_room.previous_versions.count).to eq 2
      end
    end

    describe '#previous_versions' do
      it 'is the most recent version approved' do
        expect(@live_room.previous_version).to be_blank
        @draft_room.name = 'Parlour'
        @live_room.publish_draft!
        previous_version_1 = @live_room.previous_version

        @live_room.editable_version.name = 'Library'
        @live_room.publish_draft!
        previous_version_2 = @live_room.reload.previous_version

        expect(@live_room.previous_versions).to eq [previous_version_2, previous_version_1]
      end
    end

    describe 'allowing previous versions to be saved' do
      before { Room.disable_approval! }
      subject { @previous_version }

      def setup_previous_version
        @room = Room.create name: 'Bedroom'
        expect(@room.previous_version).to be_nil
        @room.editable_version.name = 'Parlour'
        @room.publish_draft!
        @previous_version = @room.reload.previous_version
        @previous_version.name = 'Kitchen'
      end

      context 'configured to allow saving' do
        before do
          Room.requires_approval allow_previous_versions_to_be_changed: true, associations: []
          setup_previous_version
        end
        it { expect(Room::ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED).to eq true }
        it 'can be saved' do
          expect(subject.save).to be true
          expect(subject.reload.name).to eq 'Kitchen'
          expect(subject.current_approved_version).to eq @room
        end
      end

      context 'configured to prevent saving' do
        before do
          Room.requires_approval allow_previous_versions_to_be_changed: false, associations: []
          setup_previous_version
        end
        it { expect(Room::ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED).to eq false }
        it 'cannot be saved' do
          expect(subject.current_approved_version_id).to eq @room.id
          expect(subject.save).to be false
          expect(subject.reload.name).to eq 'Bedroom'
        end
      end
    end

    describe '#make_current!' do
      before do
        @draft_room.update_attributes name: 'Parlour'
        @live_room.publish_draft!
        @previous_version = @live_room.reload.previous_version
        expect(@previous_version.name).to eq 'Living Room'
      end

      it 'makes the previous version the new approved version' do
        @previous_version.make_current!
        expect(@live_room.reload.name).to eq 'Living Room'
        expect(@live_room).to_not be_is_previous_version
        expect(@live_room.approved_version_id).to be_nil
        expect(@live_room.current_approved_version_id).to be_nil
      end

      it 'adds the approved version to the version history' do
        @previous_version.make_current!
        expect(@live_room.reload.previous_version.name).to eq 'Parlour'
      end

      it 'destroys the approved versions draft' do
        draft = @live_room.editable_version
        @previous_version.make_current!
        expect(Room.where(id: draft.id)).to_not be_exists
      end
    end
  end

  describe '#draft_diff' do
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

  describe '#after_create_draft' do
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
