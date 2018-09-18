require 'activerecord_instance_methods'
require 'draft_diff_instance_methods'
require 'previous_version_instance_methods'

module DraftPunk
  module Model
    module ActiveRecordClassMethods
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
        return unless draft_punk_table_exists?(table_name) # Short circuits if you're migrating

        associations = draft_target_associations if associations.empty?
        set_valid_associations(associations)

        raise DraftPunk::ConfigurationError, "Cannot call requires_approval multiple times for #{name}" if const_defined?(:DRAFT_PUNK_IS_SETUP)
        self.const_set :DRAFT_NULLIFY_ATTRIBUTES, Array(nullify).flatten.freeze

        amoeba do
          nullify nullify
          # Note that the amoeba associations and customize options are being set in setup_associations_and_scopes_for
        end
        setup_amoeba_for self, set_default_scope: set_default_scope, allow_previous_versions_to_be_changed: allow_previous_versions_to_be_changed
        true
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

    protected #################################################################

      def default_draft_target_associations
        reflect_on_all_associations.select do |reflection|
          is_relevant_association_type?(reflection) &&
          !reflection.name.in?(%i(draft approved_version)) &&
          reflection.class_name != name # Self referential associations!!! Don't do them!
        end.map{|r| r.name.downcase.to_sym }
      end

      # Rejects the associations if the table hasn't been defined yet. This happens when
      # running migrations which add that association's table.
      def set_valid_associations(associations)
        return const_get(:DRAFT_VALID_ASSOCIATIONS) if const_defined?(:DRAFT_VALID_ASSOCIATIONS)
        associations = associations.map(&:to_sym)
        valid_assocations = associations.select do |assoc|
          reflection = reflect_on_association(assoc)
          if reflection
            table_name = reflection.klass.table_name
            draft_punk_table_exists?(table_name)
          else
            false
          end
        end
        self.const_set :DRAFT_VALID_ASSOCIATIONS, valid_assocations.freeze
        valid_assocations
      end

    private ###################################################################

      def setup_amoeba_for(target_class, options={})
        return if target_class.const_defined?(:DRAFT_PUNK_IS_SETUP)
        associations = target_class.draft_target_associations
        associations = target_class.set_valid_associations(associations)
        target_class.amoeba do
          enable 
          include_associations target_class.const_get(:DRAFT_VALID_ASSOCIATIONS) unless target_class.const_get(:DRAFT_VALID_ASSOCIATIONS).empty?
          customize target_class.set_approved_version_id_callback
        end
        target_class.const_set :DRAFT_PUNK_IS_SETUP, true.freeze

        setup_associations_and_scopes_for target_class, **options
        setup_draft_association_persistance_for_children_of target_class, associations
      end

    public ###################################################################

      def set_approved_version_id_callback
        lambda do |live_obj, draft_obj|
          draft_obj.approved_version_id = live_obj.id if draft_obj.respond_to?(:approved_version_id)
          draft_obj.temporary_approved_object = live_obj
        end
      end

    private ###################################################################

      def setup_draft_association_persistance_for_children_of(target_class, associations=nil)
        associations = target_class.draft_target_associations unless associations
        target_reflections = associations.map do |assoc|
          reflection = target_class.reflect_on_association(assoc.to_sym)
          reflection.presence || (raise DraftPunk::ConfigurationError, "#{name} includes invalid association (#{assoc})")
        end
        target_reflections.select{|r| is_relevant_association_type?(r) }.each do |assoc|
          setup_amoeba_for assoc.klass
        end
      end

      def setup_associations_and_scopes_for(target_class, set_default_scope: false, allow_previous_versions_to_be_changed: true)
        target_class.send       :include, InstanceInterrogators unless target_class.method_defined?(:has_draft?)
        target_class.send       :attr_accessor, :temporary_approved_object
        target_class.send       :before_create, :before_create_draft if target_class.method_defined?(:before_create_draft)

        target_class.const_set :ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED, allow_previous_versions_to_be_changed.freeze
        if target_class.tracks_approved_version_history?
          target_class.belongs_to    :current_approved_version, class_name: target_class.name, optional: true
          target_class.has_many      :previous_versions, -> { order(id: :desc) }, class_name: target_class.name, foreign_key: :current_approved_version_id
          target_class.before_update :prevent_previous_versions_from_saving
          target_class.send          :include, PreviousVersionInstanceMethods
        end

        if set_default_scope
          target_class.default_scope -> { approved }
        end

        return if target_class.reflect_on_association(:approved_version) || !target_class.column_names.include?('approved_version_id')
        target_class.send       :include, ActiveRecordInstanceMethods
        target_class.send       :include, DraftDiffInstanceMethods
        target_class.belongs_to :approved_version, class_name: target_class.name, optional: true
        target_class.scope      :approved, -> { where("#{target_class.quoted_table_name}.approved_version_id IS NULL") }
        target_class.has_one    :draft, -> { unscope(where: :approved) }, class_name: target_class.name, foreign_key: :approved_version_id
        target_class.scope      :draft, -> { unscoped.where("#{target_class.quoted_table_name}.approved_version_id IS NOT NULL") }
      end

      def is_relevant_association_type?(activerecord_reflection)
        activerecord_reflection.macro.in? Amoeba::Config::DEFAULTS[:known_macros]
      end

      def draft_punk_table_exists?(table_name)
        if ActiveRecord::Base.connection.respond_to? :data_source_exists?
          ActiveRecord::Base.connection.data_source_exists?(table_name)
        else
          ActiveRecord::Base.connection.table_exists?(table_name)
        end
      end
    end

  end
end