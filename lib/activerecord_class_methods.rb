require 'activerecord_instance_methods'

module DraftPunk
  module Model
    module ActiveRecordClassMethods
      # Call this method in your model to setup approval.
      #
      # Optionally pass in ALL associations which the user will edit via accepts_nested_attributes.
      # All changes to the draft, including associations, get set on the draft object.
      #
      # e.g. When editing your model (business), users updating the address, images
      #      and employees via accepts_nested_attributes. However, only the images
      #      require approval.
      # 
      #      Thus, you will use this in your model:
      #      requires_approval(associations: ['images', 'address', 'employees'])
      #
      #      If you omit address and employees, the save in your controller will fail, 
      #      since the draft object won't have an address or employees to update.
      #
      # If you want your draft associations to track their live version, add an :approved_version_id column
      # to each association's table. You'll be able to access that associated object's live version, just
      # like you can with the original model which called requires_approval. 
      #
      def requires_approval(associations: [], nullify: [])
        send :include, ActiveRecordInstanceMethods
        send :include, InstanceInterrogators
                                         
        associations = reflect_on_all_associations.select{|r| is_relevant_association_type?(r) && !r.name.in?(%i(draft approved_version)) }.map{|r| r.name.downcase } if associations.empty?
        associations = associations.map(&:to_sym)

      	raise DraftPunk::ConfigurationError, "Cannot call requires_approval multiple times for #{name}" if const_defined? :DRAFT_EDITABLE_ASSOCIATIONS
        self.const_set :DRAFT_EDITABLE_ASSOCIATIONS, associations

        amoeba do
          include_association associations
          nullify nullify
          # Note that the amoeba customize option is being set in setup_associations_and_scopes_for
        end
        setup_associations_and_scopes_for self
        setup_draft_association_persistance_for self, associations

        associations.each do |assoc|
          reflection = reflect_on_association(assoc)
          raise DraftPunk::ConfigurationError, "#{name} requires_approval includes invalid association (#{assoc})" unless reflection
          target_class = reflection.class_name.constantize
          target_class.amoeba do
            exclude_association :approved_version
            exclude_association :draft
            # Note that the amoeba customize option is being set in setup_associations_and_scopes_for
          end
          setup_draft_association_persistance_for target_class
          setup_associations_and_scopes_for target_class
        end
      end

      def accepts_nested_drafts_for(associations=nil)
        raise DraftPunk::ConfigurationError, "#{name} accepts_nested_drafts_for must include names of associations to create drafts for" unless associations
      	raise DraftPunk::ConfigurationError, "Cannot call accepts_nested_drafts_for multiple times for #{name}" if const_defined? :DRAFT_EDITABLE_ASSOCIATIONS

        associations = [associations].flatten
        associations.each do |assoc|
          raise DraftPunk::ConfigurationError, "#{name} accepts_nested_drafts_for includes invalid association (#{assoc})" unless reflect_on_association(assoc)
        end
        self.const_set :DRAFT_EDITABLE_ASSOCIATIONS, associations
        amoeba do
          include_association associations
        end
      end

      # This will generally be only used in testing scenarios
      def disable_approval!
      	return unless const_defined? :DRAFT_EDITABLE_ASSOCIATIONS
    		send(:remove_const, :DRAFT_EDITABLE_ASSOCIATIONS)
    		@config_block = nil # @config_block is used/set by amoeba gem
      end

      private ####################################################################

      def setup_draft_association_persistance_for(target_class, associations=nil)
        target_reflections = if associations
          associations.map do |assoc|
            reflection = target_class.reflect_on_association(assoc)
            raise DraftPunk::ConfigurationError, "#{name} includes invalid association (#{assoc})" unless reflection
            reflection
          end
        else
          target_class.reflect_on_all_associations
        end
        target_reflections.select{|r| is_relevant_association_type?(r) }.each do |assoc|
          assoc.klass.send :include, InstanceInterrogators
          assoc.klass.amoeba do
            customize(lambda {|live_obj, draft_obj|
              draft_obj.approved_version_id = live_obj.id if draft_obj.respond_to?(:approved_version_id)
            })
          end
        end
      end

      def setup_associations_and_scopes_for(target_class)
        return if target_class.reflect_on_association(:approved_version) || !target_class.column_names.include?('approved_version_id')
        target_class.belongs_to :approved_version, class_name: target_class.name
        target_class.has_one    :draft, class_name: target_class.name, foreign_key: :approved_version_id, unscoped: true
        target_class.scope      :approved, -> { where("#{target_class.quoted_table_name}.approved_version_id IS NULL") }
        target_class.scope      :draft,    -> { unscoped.where("#{target_class.quoted_table_name}.approved_version_id IS NOT NULL") }
        target_class.send       :include, InstanceInterrogators
      end

      def is_relevant_association_type?(activerecord_reflection)
        # Note when implementing for Rails 4, macro is renamed to something else
        activerecord_reflection.macro.in? Amoeba::Config::DEFAULTS[:known_macros]
      end
    end
  end
end