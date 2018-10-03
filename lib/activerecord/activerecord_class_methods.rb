module DraftPunk
  module Model
  	module ActiveRecordClassMethods
      # List of association names this model is configured to have drafts for
      # @return [Array]
      def draft_target_associations
        targets = if const_defined?(:CREATES_NESTED_DRAFTS_FOR) && const_get(:CREATES_NESTED_DRAFTS_FOR).is_a?(Array)
          const_get(:CREATES_NESTED_DRAFTS_FOR).compact
        else
          default_draft_target_associations
        end.map(&:to_sym)
      end

      # Whether this model is configured to track the approved version of a draft object.
      # This will be true if the model has an approved_version_id column
      #
      # @return (Boolean)
      def tracks_approved_version?
        column_names.include? 'approved_version_id'
      end

      # Whether this model is configured to store previously-approved versions of the model.
      # This will be true if the model has an current_approved_version_id column
      #
      # @return (Boolean)
      def tracks_approved_version_history?
        column_names.include?('current_approved_version_id')
      end

      # Callback runs after save to set the approved version id on the draft object.
      #
      # @return (true)
      def set_approved_version_id_callback
        lambda do |live_obj, draft_obj|
          draft_obj.approved_version_id = live_obj.id if draft_obj.respond_to?(:approved_version_id)
          draft_obj.temporary_approved_object = live_obj
          true
        end
      end

    protected #################################################################

      def default_draft_target_associations
        reflect_on_all_associations.select do |reflection|
          DraftPunk.is_relevant_association_type?(reflection) &&
          !reflection.name.in?(%i(draft approved_version)) &&
          reflection.class_name != name # Self referential associations!!! Don't do them!
        end.map{|r| r.name.downcase.to_sym }
      end
  	end
  end
end