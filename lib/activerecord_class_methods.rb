require 'activerecord_instance_methods'

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
      # Optionally pass in only associations which the user will edit - associations which should have a draft created.
      # If you only want the :address association to have a draft created, call this, instead, in your model.
      #  
      #  requires_approval associations: [:address]
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
      # @param associations [Array] Pass in ALL associations which the user will need to edit. If not supplied, all 
      #    :has_many, :has_one, and :has_and_belongs_to_many associations for this model, and its children, will be used.
      # @param nullify [Array] A list of attributes on this model to set to null on the draft when it is created. For
      #    instance, the _id_ and _created_at_ columns are nullified by default, since you don't want Rails to try to
      #    persist those on the draft.
      # @return nil
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

      # Call this on any associations of your primary associated object to control which of _this_ model's associations
      # to create drafts for.
      #
      # For instance, your Business has a has_many association to Employee
      #
      #  class Business << ActiveRecord::Base
      #    has_many :employees
      #    has_many :images
      #    has_one  :address
      #    has_many :vending_machines
      #
      #    requires_approval # When creating a business's draft, :employees, :vending_machines, :images, and :address will all have drafts created
      #  end
      # And you want people to be able to edit a draft of their home address. But they WON'T be editing their
      # confidential_browsing_activities. So, let's exclude that from the drafts.
      #  class Employee << ActiveRecord::Base
      #    belongs_to :business
      #    has_one  :home_address
      #    has_many :confidential_browsing_activities
      #
      #    accepts_nested_drafts_for :home_address
      #  end
      # 
      # @param associations [Array] Pass in all associations which a draft will be created for.
      # @return nil
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

      # This will generally be only used in testing scenarios, in cases when requires_approval need to be
      # called multiple times. Only the usage for that use case is supported. Use at your own risk for other
      # use cases.
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