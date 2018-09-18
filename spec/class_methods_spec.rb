require 'spec_helper'

describe DraftPunk::Model::ActiveRecordClassMethods do

  context :valid_arguments do

    describe '.requires_approval' do
      after { disable_all_approvals }

      it "works if the class has no associations" do
        Apartment.requires_approval
        apartment = Apartment.create(name: '450 5th Avenue')
        expect(apartment.editable_version.is_draft?).to be true
      end
      it 'sets editable associations for all in the CREATES_NESTED_DRAFTS_FOR constant' do
        House.requires_approval
        expect(House.draft_target_associations.sort).to eq House::CREATES_NESTED_DRAFTS_FOR.sort
      end
      it 'sets all associations as editable if no associations explicity provided' do
        stub_const("House::CREATES_NESTED_DRAFTS_FOR", nil)
        House.requires_approval
        expect(House.draft_target_associations.sort).to eq %i(permits rooms)
      end
      it "works if a specified association doesn't exist" do
        stub_const("House::CREATES_NESTED_DRAFTS_FOR", [:widgets])
        expect { House.requires_approval }.to_not raise_error
      end
      it "works if nullify argument is empty" do
        expect { House.requires_approval }.to_not raise_error
      end
    end
  end

  describe '.tracks_approved_version?' do
    it "is false if the table doesn't have an attribute to track approved version" do
      Permit.requires_approval
      expect(Permit.column_names).to_not include('approved_version_id')
      expect(Permit.tracks_approved_version?).to be false
    end

    it "is true if the table has an attribute to track approved version" do
      expect(House.column_names).to include('approved_version_id')
      expect(House.tracks_approved_version?).to be true
    end
  end

  describe '.tracks_approved_version_history?' do
    it "is false if the table doesn't have an attribute to track approved version" do
      expect(House.column_names).to_not include('current_approved_version_id')
      expect(House.tracks_approved_version_history?).to be false
    end

    it "is true if the table has an attribute to track approved version" do
      expect(Room.column_names).to include('current_approved_version_id')
      expect(Room.tracks_approved_version_history?).to be true
    end
  end

  context :valid_configuration do
    before(:all)  { setup_model_approvals }
    before        { setup_house_with_draft }

    context :setup do
      it 'has a house with two rooms and a permit' do
        h = House.first 
        expect(h).to eq @house
        expect(h.rooms.count).to eq 2
        expect(h.rooms.pluck(:name).sort).to eq ['Entryway', 'Living Room']
        expect(h.permits.count).to eq 1
      end
      it 'has an approved_version_id for the right models' do
        [House, Room, Closet].each do |model|
          expect(model.column_names).to include('approved_version_id')
        end
      end
    end

    context 'public class methods' do
      context :requires_approval do
        it "doesn't modify the original object when a draft is created" do
          expect(House.find @house.id).to eq @house
        end

        it 'creates draft copies of all associations specified in requires_approval associations argument' do
          expect(@draft.rooms.count).to eq 2
          expect(@draft.permits.count).to be_zero 
        end

        it 'nullifies all attributes specified in requires_approval nullify_attributes argument' do
          expect(@house.address).to be_present
          expect(@draft.address).to be_nil
        end

        it 'returns approved versions of the object via the approved scope' do
          expect(House.count).to eq 2
          expect(House.approved.count).to eq 1
        end

        it 'returns draft versions of the object via the draft scope' do
          expect(House.count).to eq 2
          expect(House.draft.count).to eq 1
        end
      end

      context '.accepts_nested_drafts_for' do
        it 'creates draft copies of all associations specified in the associations argument' do
          draft_room = @draft.rooms.where(name: 'Living Room').first
          expect(draft_room.closets.count    ).to eq(2)
          expect(draft_room.trim_styles.count).to eq(1)
        end
        it "doesn't draft copies of all associations not specified in the associations argument" do
          draft_room = @draft.rooms.where(name: 'Living Room').first
          expect(draft_room.electrical_outlets.count).to be_zero
        end
      end
    end
  end
end