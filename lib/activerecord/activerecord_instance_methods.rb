module DraftPunk
  module Model
    module ActiveRecordInstanceMethods
      #############################
      # BEGIN CONFIGURABLE METHODS
      # You can overwrite these methods in your model for custom behavior
      #############################

      # Which attributes of this model are published from the draft to the approved object. Overwrite in model
      # if you don't want all attributes of the draft to be saved on the live object.
      #
      # This is an array of attributes (including has_one association id columns) which will be saved 
      # on the object when its' draft is approved.
      #
      # For instance, if you want to omit updated_at, for whatever reason, you would define this in your model:
      #
      #  def approvable_attributes
      #    self.attributes.keys - ["created_at", "updated_at"]
      #  end
      #
      # WARNING: Don't include "created_at" if you don't want to modify this object's created_at!
      #
      # @return [Array] names of approvable attributes
      def approvable_attributes
        self.attributes.keys - ["created_at"]
      end

      # Determines whether to edit a draft, or the original object. This only controls
      # the object returned by editable version, and draft publishing. If changes to not
      # require approval, publishing of the draft is short circuited and will do nothing.
      #
      # Overwrite in your model to implement logic for whether to use a draft.
      #
      # @return [Boolean]
      def changes_require_approval?
        true # By default, all changes require approval
      end

      # Evaluates after the draft is created.
      # Override in your model to implement custom behavior.
      def after_create_draft
      end

      #############################
      # END CONFIGURABLE METHODS
      #############################


      # Updates the approved version with any changes on the draft, and all the drafts' associated objects.
      # 
      # If the approved version changes_require_approval? returns false, this method exits early and does nothing
      # to the approved version.
      #
      # THE DRAFT VERSION IS DESTROYED IN THIS PROCESS. To generate a new draft, simply call <tt>editable_version</tt>
      # again on the approved object.
      # 
      # @return [ActiveRecord Object] updated version of the approved object
      def publish_draft!
        @live_version  = get_approved_version
        @draft_version = editable_version
        return unless changes_require_approval? && @draft_version.is_draft? # No-op. ie. the live version is in a state that doesn't require approval.
        transaction do
          create_historic_version_of_approved_object if tracks_approved_version_history?
          save_attribute_changes_and_belongs_to_assocations_from_draft
          update_has_many_and_has_one_associations_from_draft
          # We have to destroy the draft this since we moved all the draft's has_many associations to @live_version. If you call "editable_version" later, it'll build the draft.
          # We destroy_all in case extra drafts are in the database. Extra drafts can potentially be created due to race conditions in the application.
          self.class.unscoped.where(approved_version_id: @live_version.id).destroy_all
        end
        @live_version = self.class.find(@live_version.id)
      end

      # Get the object's draft if changes require approval; this method creates one if it doesn't exist yet
      # If changes do not require approval, the original approved object is returned
      #
      # @return ActiveRecord Object
      def editable_version
        return get_approved_version unless changes_require_approval?
        is_draft? ? self : get_draft
      end

      # Get the approved version. Intended for use on a draft object, but works on a live/approved object too
      #
      # @return (ActiveRecord Object)
      def get_approved_version
        approved_version || self
      end

      def tracks_approved_version_history?
        self.class.tracks_approved_version_history?
      end

    protected #################################################################

      def get_draft
        draft || create_draft_version
      end

    private ####################################################################

      def create_draft_version
        # Don't call this directly. Use editable_version instead.
        return draft if draft.present?
        dupe = amoeba_dup
        begin
          dupe.approved_version = self
          dupe.save(validate: false)
          dupe.after_create_draft
        rescue => message
          raise DraftCreationError, message
        end
        reload
        draft
      end

      def create_historic_version_of_approved_object
        begin
          dupe = @live_version.amoeba_dup
          dupe.assign_attributes(
                     approved_version_id: nil,
             current_approved_version_id: @live_version.id,
                              created_at: @live_version.created_at,
                              updated_at: @live_version.updated_at )
          dupe.save!(validate: false)
        rescue => message
          raise HistoricVersionCreationError, message
        end
        true
      end

      def save_attribute_changes_and_belongs_to_assocations_from_draft
        @draft_version.attributes.each do |attribute, value|
          next unless attribute.in? usable_approvable_attributes
          @live_version.send("#{attribute}=", value)
        end
        @live_version.before_publish_draft if @live_version.respond_to?(:before_publish_draft)
        @live_version.save(validate: false)
      end

      def update_has_many_and_has_one_associations_from_draft
        self.class.draft_target_associations.each do |assoc|
          reflection = self.class.reflect_on_association(assoc) || next
          reflection_is_has_many(reflection) ? @live_version.send(assoc).destroy_all : @live_version.send(assoc).try(:destroy)

          attribute_updates = {}
          attribute_updates[reflection.foreign_key] = @live_version.id
          attribute_updates['updated_at']           = Time.now if reflection.klass.column_names.include?('updated_at')
          attribute_updates['approved_version_id']  = nil if reflection.klass.tracks_approved_version?

          if reflection_is_has_many(reflection)
            @draft_version.send(assoc).update_all attribute_updates
          elsif @draft_version.send(assoc).present?
            @draft_version.send(assoc).update_columns attribute_updates
          end
        end
      end

      def usable_approvable_attributes
        nullified_attributes = self.class.const_defined?(:DRAFT_NULLIFY_ATTRIBUTES) ? self.class.const_get(:DRAFT_NULLIFY_ATTRIBUTES) : []
        approvable_attributes.map(&:to_s) - nullified_attributes.map(&:to_s) - ['approved_version_id', 'id', 'current_approved_version_id']
      end

      def current_approvable_attributes
        attribs = {}
        attributes.each do |k,v|
          attribs[k] = v if k.in?(diff_relevant_attributes)
        end
      end

      def association_tracks_approved_version?(name)
        self.class.reflect_on_association(name.to_sym).klass.column_names.include? 'approved_version_id'
      end

      def association_is_has_many(name)
        self.class.reflect_on_association(name.to_sym).macro == :has_many
      end

      def reflection_is_has_many(reflection)
        reflection.macro == :has_many
      end
    end

    module InstanceInterrogators
      # @return [Boolean] whether the current ActiveRecord object is a draft
      def is_draft?
        raise DraftPunk::ApprovedVersionIdError unless respond_to?("approved_version_id")
        approved_version_id.present?
      end

      # @return [Boolean] whether the current ActiveRecord object has a draft version
      def has_draft?
        raise DraftPunk::ApprovedVersionIdError unless respond_to?(:approved_version_id)
        draft.present?
      end

      # @return [Boolean] whether the current ActiveRecord object is a previously-approved
      #    version of another instance of this class
      def is_previous_version?
        tracks_approved_version_history? &&
        !is_draft? &&
        current_approved_version_id.present?
      end
    end
  end
end