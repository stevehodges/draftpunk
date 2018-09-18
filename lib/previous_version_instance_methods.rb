module DraftPunk
  module Model
    module PreviousVersionInstanceMethods

      # If the current object A is in the previous version history of a
      # object B, this method updates B to match the approvable attributes
      # and associations of A. A copy of B is added to the previous version
      # history.
      #
      # @return [Activerecord Object] updated version of the approved object
      def make_current!
        return unless is_previous_version?
        @live_version = current_approved_version
        @previous_version = self
        @live_version.draft.try(:destroy)
        @previous_version.update_attributes(
          current_approved_version_id: nil,
                     approved_version: @live_version)
        @live_version.publish_draft!
      end

      # @return [Activerecord Object]
      def previous_version
        previous_versions.first
      end

    private ###################################################################

      # before_save
      def prevent_previous_versions_from_saving
        if is_previous_version? &&
          self.class.const_defined?(:ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED) &&
          !self.class::ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED
          errors.add :base, 'cannot save previously approved version'
          throw :abort 
        end
      end

    end
  end
end