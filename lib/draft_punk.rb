require 'draft_punk/version'
require 'amoeba'
require 'activerecord_class_methods'
require 'helper_methods'

module DraftPunk
  module Model
    def self.included(base)
      base.send :extend, ActiveRecordClassMethods
    end
  end

  class ConfigurationError < RuntimeError
    def initialize(message)
    	@caller = caller[0]
      @message = message
    end
    def to_s
      "#{@caller} error: #{@message}"
    end
  end

  class ApprovedVersionIdError < ArgumentError
    def initialize(message=nil)
      @message = message
    end
    def to_s
      "this model doesn't have an approved_version_id column, so you cannot access its draft or approved versions. Add a column approved_version_id (Integer) to enable this tracking."
    end
  end

  class HistoricVersionCreationError < ArgumentError
    def initialize(message=nil)
      @message = message
    end
    def to_s
      "could not create previously-approved version: #{@message}"
    end
  end

  class DraftCreationError < ActiveRecord::RecordInvalid
    def initialize(message)
      @message = message
    end
    def to_s
      "the draft failed to be created: #{@message}"
    end
  end

end

ActiveSupport.on_load(:active_record) do
  include DraftPunk::Model
end
