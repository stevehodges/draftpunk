module DraftPunk

  def self.is_relevant_association_type?(activerecord_reflection)
    activerecord_reflection.macro.in? Amoeba::Config::DEFAULTS[:known_macros]
  end

	class SetupModel
		require_relative 'activerecord_class_methods'
		require_relative 'activerecord_instance_methods'
		require_relative 'draft_diff_instance_methods'
		require_relative 'previous_version_instance_methods'

		def initialize(top_level_model, associations: [], nullify: [], set_default_scope: false, allow_previous_versions_to_be_changed: true)
			@top_level_model, @associations, @nullify = top_level_model, associations, nullify
			@set_default_scope, @allow_previous_versions_to_be_changed = set_default_scope, allow_previous_versions_to_be_changed
		end

		def make_approvable!
      return unless model_table_exists? # Short circuits if you're migrating
      @top_level_model.extend Model::ActiveRecordClassMethods

      @associations = @top_level_model.draft_target_associations if @associations.empty?
      set_valid_associations @top_level_model, @associations

      raise DraftPunk::ConfigurationError, "Cannot call requires_approval multiple times for #{@top_level_model.name}" if @top_level_model.const_defined?(:DRAFT_PUNK_IS_SETUP)
      @top_level_model.const_set :DRAFT_NULLIFY_ATTRIBUTES, Array(@nullify).flatten.freeze
      @top_level_model.amoeba do
        nullify @nullify
        # Note that the amoeba associations and customize options are being set in setup_associations_and_scopes_for
      end
      setup_amoeba_for @top_level_model, set_default_scope: @set_default_scope, allow_previous_versions_to_be_changed: @allow_previous_versions_to_be_changed
      true
		end

	private #####################################################################

    def model_table_exists?(table_name=@top_level_model.table_name)
      if ActiveRecord::Base.connection.respond_to? :data_source_exists?
        ActiveRecord::Base.connection.data_source_exists?(table_name)
      else
        ActiveRecord::Base.connection.table_exists?(table_name)
      end
    end

    def setup_amoeba_for(target_model, options={})
      return if target_model.const_defined?(:DRAFT_PUNK_IS_SETUP)
			target_model.extend Model::ActiveRecordClassMethods
      target_associations = target_model.draft_target_associations
      target_associations = set_valid_associations(target_model, target_associations)
      target_model.amoeba do
        enable 
        include_associations target_model.const_get(:DRAFT_VALID_ASSOCIATIONS) unless target_model.const_get(:DRAFT_VALID_ASSOCIATIONS).empty?
        customize target_model.set_approved_version_id_callback
      end
      target_model.const_set :DRAFT_PUNK_IS_SETUP, true.freeze

      setup_associations_and_scopes_for target_model, **options
      setup_draft_association_persistance_for_children_of target_model, target_associations
    end

    def setup_associations_and_scopes_for(target_model, set_default_scope: false, allow_previous_versions_to_be_changed: true)
      target_model.send       :include, Model::InstanceInterrogators unless target_model.method_defined?(:has_draft?)
      target_model.send       :attr_accessor, :temporary_approved_object
      target_model.send       :before_create, :before_create_draft if target_model.method_defined?(:before_create_draft)

      target_model.const_set :ALLOW_PREVIOUS_VERSIONS_TO_BE_CHANGED, allow_previous_versions_to_be_changed.freeze
      if target_model.tracks_approved_version_history?
        target_model.belongs_to    :current_approved_version, class_name: target_model.name, optional: true
        target_model.has_many      :previous_versions, -> { order(id: :desc) }, class_name: target_model.name, foreign_key: :current_approved_version_id
        target_model.before_update :prevent_previous_versions_from_saving
        target_model.send          :include, Model::PreviousVersionInstanceMethods
      end

      if set_default_scope
        target_model.default_scope -> { approved }
      end

      return if target_model.reflect_on_association(:approved_version) || !target_model.column_names.include?('approved_version_id')
      target_model.send       :include, Model::ActiveRecordInstanceMethods
      target_model.send       :include, Model::DraftDiffInstanceMethods
      target_model.belongs_to :approved_version, class_name: target_model.name, optional: true
      target_model.scope      :approved, -> { where("#{target_model.quoted_table_name}.approved_version_id IS NULL") }
      target_model.has_one    :draft, -> { unscope(where: :approved) }, class_name: target_model.name, foreign_key: :approved_version_id
      target_model.scope      :draft, -> { unscoped.where("#{target_model.quoted_table_name}.approved_version_id IS NOT NULL") }
    end

    def setup_draft_association_persistance_for_children_of(target_model, target_associations=nil)
      target_associations = target_model.draft_target_associations unless target_associations
      target_reflections = target_associations.map do |assoc|
        reflection = target_model.reflect_on_association(assoc.to_sym)
        reflection.presence || (raise DraftPunk::ConfigurationError, "#{name} includes invalid association (#{assoc})")
      end
      target_reflections.select{|r| DraftPunk.is_relevant_association_type?(r) }.each do |assoc|
        setup_amoeba_for assoc.klass
      end
    end

    # Rejects the associations if the table hasn't been defined yet. This happens when
    # running migrations which add that association's table.
    def set_valid_associations(target_model, associations)
      return target_model.const_get(:DRAFT_VALID_ASSOCIATIONS) if target_model.const_defined?(:DRAFT_VALID_ASSOCIATIONS)
      associations = associations.map(&:to_sym)
      valid_assocations = associations.select do |assoc|
        reflection = target_model.reflect_on_association(assoc)
        if reflection
          table_name = reflection.klass.table_name
          model_table_exists?(table_name)
        else
          false
        end
      end
      target_model.const_set :DRAFT_VALID_ASSOCIATIONS, valid_assocations.freeze
      valid_assocations
    end
	end
end