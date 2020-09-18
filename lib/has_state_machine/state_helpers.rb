# frozen_string_literal: true

module HasStateMachine
  module StateHelpers
    extend ActiveSupport::Concern

    included do
      attr_accessor :skip_state_validations

      delegate \
        :state_attribute,
        :state_validations_on_object?,
        :workflow_namespace,
        :workflow_states,
        to: "self.class"

      ##
      # Sets the default value of the state method to the initial state
      # defined in the state machine.
      attribute state_attribute, :string, default: initial_state

      ##
      # Validating any changes to the status attribute are represented by
      # classes within the state machine and have a valid HasStateMachine::State class.
      validates state_attribute, inclusion: {in: workflow_states}, presence: true
      validate :state_class_defined?
      validate :state_instance_validations, if: :should_validate_state?

      ##
      # Overwrites the default getter for the state attribute to
      # instantiate a HasStateMachine::State instance instead. If the state
      # class does not exist, it simply returns a string.
      #
      # @return [HasStateMachine::State] the current state represented by a instance
      #
      # @example
      #   post = Post.new(status: "draft")
      #   post.status.class #=> Workflow::Post::Draft
      define_method state_attribute.to_s do
        return state_class.new(self) if state_class.present?

        current_state
      end

      workflow_states.each do |state|
        ##
        # Defines scopes based on the state machine possible states
        #
        # @return [ActiveRecord_Relation]
        # @example Retreiving a users published posts
        #   > Post.published.where(user: user)
        #   #=> [#<Post>]
        scope state, -> { where("#{state_attribute} = ?", state) }

        ##
        # Defines boolean helpers to determine if the active state matches
        # the specified state.
        #
        # @return [Boolean] whether or not the active state matches the call
        # @example Check if a post is published
        #   > post.published?
        #   #=> true
        define_method "#{state}?" do
          current_state == state
        end
      end

      private

      ##
      # Getter for the current state of the model based on the configured state
      # attribute.
      def current_state
        self[state_attribute]
      end

      ##
      # Predicate method for determining whether or not the state validations
      # should be run as part of the object validations.
      def should_validate_state?
        return false unless state_validations_on_object?

        !skip_state_validations
      end

      ##
      # Gets the HasStateMachine::State class that represents the current state
      # of the model.
      def state_class
        return unless current_state.present?

        "#{workflow_namespace}::#{current_state.classify}".safe_constantize
      end

      ##
      # True unless unable to find the HasStateMachine::State class for the current
      # state.
      def state_class_defined?
        return if state_class.present?

        errors.add(state_attribute, :not_implemented, message: "class must be implemented")
      end

      ##
      # Runs the validations defined on the current HasStateMachine::State when calling
      # model.valid?
      def state_instance_validations
        return unless state_class.present?

        public_send(state_attribute.to_s).valid?
      end
    end

    class_methods do
      private

      ##
      # The initial state of the workflow based on the first state defined in the model
      # has_state_machine states array.
      def initial_state
        workflow_states.first
      end
    end
  end
end
