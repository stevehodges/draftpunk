require 'spec_helper'

describe 'GemSetup' do
  context :gem_configuration do
    it 'has a version number' do
      expect(DraftPunk::VERSION).not_to be nil
    end
  end

  context :test_setup do
    it 'has models backed by a database' do
      House.is_a?(Class).should == true
      House.column_names.should include('architectual_style')
      House.column_names.should include('approved_version_id')
      House.new.should respond_to(:rooms)
      Room.new.should  respond_to(:house)
      Room.new.should  respond_to(:closets)
      Room.new.should  respond_to(:electrical_outlets)
      Room.new.should  respond_to(:custom_flooring_style)
    end
  end
end