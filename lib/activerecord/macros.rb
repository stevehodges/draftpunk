require_relative 'setup_model'

module DraftPunk
  module Model
    module Macros
      # Call this method in your model to setup approval. It will recursively apply to its associations,
      # thus does not need to be explicity called on its associated models (and will error if you try).
      #
      # This model must have an approved_version_id column (Integer), which will be used to track its draft
      # 
      # For instance, your Business model:
      #  class Business << ActiveRecord::Base
      #    has_many :employees
      #    has_many :images
      #    has_one  :address
      #    has_many :vending_machines
      #
      #    requires_approval # When creating a business's draft, :employees, :vending_machines, :images, and :address will all have drafts created
      #  end
      #
      # Optionally, specify which associations which the user will edit - associations which should have a draft created
      # by defining a CREATES_NESTED_DRAFTS_FOR constant for this model.
      #  
      #  CREATES_NESTED_DRAFTS_FOR = [:address] # When creating a business's draft, only :address will have drafts created
      #
      # To disable drafts for all assocations for this model, simply pass an empty array:
      # by defining a CREATES_NESTED_DRAFTS_FOR constant for this model.
      #  CREATES_NESTED_DRAFTS_FOR = [] # When creating a business's draft, no associations will have drafts created
      #
      # WARNING: If you are setting associations via accepts_nested_attributes all changes to the draft, including associations, get set on the
      # draft object (as expected). If your form includes associated objects which weren't defined in requires_approval, your save will fail since
      # the draft object doesn't HAVE those associations to update! In this case, you should probably add that association to the
      # +associations+ param here.
      #
      # If you want your draft associations to track their live version, add an :approved_version_id column
      # to each association's table. You'll be able to access that associated object's live version, just
      # like you can with the original model which called requires_approval. 
      #
      # @param nullify [Array] A list of attributes on this model to set to null on the draft when it is created. For
      #    instance, the _id_ and _created_at_ columns are nullified by default, since you don't want Rails to try to
      #    persist those on the draft.
      # @param set_default_scope [Boolean] If true, set a default scope on this model for the approved scope; only approved objects
      #    will be returned in ActiveRecord queries, unless you call Model.unscoped
      # @param allow_previous_versions_to_be_changed [Boolean] If the model tracks approved version history, and this
      #    param is false, previously-approved versions of the object cannot be saved (via a before_save callback )
      # @param associations [Array] Use internally; set associations to create drafts for in the CREATES_NESTED_DRAFTS_FOR constant
      # @return true
      def requires_approval(associations: [], nullify: [], set_default_scope: false, allow_previous_versions_to_be_changed: true)
        DraftPunk::SetupModel.new(self,
                                   associations: associations,
                                        nullify: nullify,
                              set_default_scope: set_default_scope,
          allow_previous_versions_to_be_changed: allow_previous_versions_to_be_changed
        ).make_approvable!
      end

      # This will generally be only used in testing scenarios, in cases when requires_approval need to be
      # called multiple times. Only the usage for that use case is supported. Use at your own risk for other
      # use cases.
      def disable_approval!
        send(:remove_const, :DRAFT_PUNK_IS_SETUP)                   if const_defined? :DRAFT_PUNK_IS_SETUP
        send(:remove_const, :DRAFT_NULLIFY_ATTRIBUTES)              if const_defined? :DRAFT_NULLIFY_ATTRIBUTES
        send(:remove_const, :ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED) if const_defined? :ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED
        fresh_amoeba do
          disable
        end
      end
    end
  end
end