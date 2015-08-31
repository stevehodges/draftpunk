require 'spec_helper'

describe DraftPunk::Model::ActiveRecordClassMethods do

  context :valid_arguments do

    context :requires_approval do
      after(:each) do
        disable_all_approvals
      end
      it "works if the class has no associations" do
        Apartment.requires_approval
        apartment = Apartment.create(name: '450 5th Avenue')
        apartment.editable_version.is_draft?.should be_truthy
      end
      it 'sets editable associations for all in the CREATES_NESTED_DRAFTS_FOR constant' do
        House.requires_approval
        House.draft_target_associations.sort.should == House::CREATES_NESTED_DRAFTS_FOR.sort
      end
      it 'sets all associations as editable if no associations explicity provided' do
        stub_const("House::CREATES_NESTED_DRAFTS_FOR", nil)
        House.requires_approval
        House.draft_target_associations.sort.should == %i(permits rooms)
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
        [House, Room, Closet].each do |model|
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
          draft_room.closets.count.should be(2)
          draft_room.trim_styles.count.should be(1)
        end
        it "doesn't draft copies of all associations not specified in the associations argument" do
          draft_room = @draft.rooms.where(name: 'Living Room').first
          draft_room.electrical_outlets.count.should be(0)
        end
      end
    end
  end
end