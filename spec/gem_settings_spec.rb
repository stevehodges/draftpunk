require 'spec_helper'

describe 'GemSetup' do
  context :gem_configuration do
    it 'has a version number' do
      expect(DraftPunk::VERSION).not_to be nil
    end
  end

  context :test_setup do
    it { expect(House.is_a?(Class)).to eq true }
    it { expect(House.column_names).to include('architectual_style') }
    it { expect(House.column_names).to include('approved_version_id') }
    it { expect(House.new).to respond_to(:rooms) }
    it { expect(Room.new ).to respond_to(:house) }
    it { expect(Room.new ).to respond_to(:closets) }
    it { expect(Room.new ).to respond_to(:electrical_outlets) }
    it { expect(Room.new ).to respond_to(:custom_flooring_style) }
  end
end