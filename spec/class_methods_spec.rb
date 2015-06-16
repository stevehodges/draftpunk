require 'spec_helper'

MODELS_WITH_APPROVED_VERSION_ID = [House, Room, Closet, FlooringStyle]

describe DraftPunk::Model::ActiveRecordClassMethods do

  context :valid_arguments do

    context :requires_approval do
      after(:each) do
        House.disable_approval!
      end
      it 'sets editable associations for all in the associations argument' do
        House.requires_approval associations: House::APPROVABLE_ASSOCIATIONS
        House::DRAFT_EDITABLE_ASSOCIATIONS.sort.should == House::APPROVABLE_ASSOCIATIONS.sort
      end
      it 'sets all associations as editable if no associations explicity provided' do
        House.requires_approval
        House::DRAFT_EDITABLE_ASSOCIATIONS.sort.should == %i(permits rooms)
      end
      it "raises a Configuration Error if a specified association doesn't exist" do
        expect { House.requires_approval(associations: [:widgets])}.to raise_error(DraftPunk::ConfigurationError)
      end
      it "works if nullify argument is empty" do
        expect { House.requires_approval associations: House::APPROVABLE_ASSOCIATIONS}.to_not raise_error
      end
    end

    context :accepts_nested_drafts_for do
      after(:each) do
        Room.disable_approval!
      end
      it 'sets editable associations for all in the first argument' do
        Room.accepts_nested_drafts_for Room::APPROVABLE_ASSOCIATIONS
        Room::DRAFT_EDITABLE_ASSOCIATIONS.sort.should == Room::APPROVABLE_ASSOCIATIONS.sort
      end
      it 'raises a Configuration Error if no associations are passed as an argument' do
        expect { Room.accepts_nested_drafts_for }.to raise_error(DraftPunk::ConfigurationError)
      end
      it "raises a Configuration Error if a specified association doesn't exist" do
        expect { Room.accepts_nested_drafts_for [:widgets]}.to raise_error(DraftPunk::ConfigurationError)
      end
    end
  end

  context :valid_configuration do
    before(:all)  { setup_model_approvals }
    before(:each) { setup_house_with_draft }

    context :setup do
      it 'has a house with two rooms and a permit' do
        h = House.first 
        h.should == @house
        h.rooms.count.should be(2)
        h.rooms.pluck(:name).sort.should == ['Entryway', 'Living Room']
        h.permits.count.should be(1)
      end
      it 'should have an approved_version_id for the right models' do
        MODELS_WITH_APPROVED_VERSION_ID.each do |model|
          model.column_names.should include('approved_version_id')
        end
      end
    end

    context 'public class methods' do
      context :requires_approval do
        it "doesn't modify the original object when a draft is created" do
          reloaded_house = House.find @house.id
          reloaded_house.should == @house
        end

        it 'creates draft copies of all associations specified in requires_approval associations argument' do
          @draft.rooms.count.should be(2)
          @draft.permits.count.should be(0)
        end

        it 'nullifies all attributes specified in requires_approval nullify_attributes argument' do
          @house.address.should be_present
          @draft.address.should be_nil
        end

        it 'returns approved versions of the object via the approved scope' do
          House.count.should be(2)
          House.approved.count.should be(1)
        end

        it 'returns draft versions of the object via the draft scope' do
          House.count.should be(2)
          House.draft.count.should be(1)
        end
      end

      context :accepts_nested_drafts_for do
        it 'creates draft copies of all associations specified in the associations argument' do
          draft_room = @draft.rooms.where(name: 'Living Room').first
          draft_room.electrical_outlets.count.should be(0)
          draft_room.closets.count.should be(2)
          draft_room.trim_styles.count.should be(1)
        end
      end
    end
  end
end