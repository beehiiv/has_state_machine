# frozen_string_literal: true

require "active_support/core_ext/string"

module HasStateMachine
  class State < String
    extend ActiveModel::Model
    extend ActiveModel::Callbacks
    include ActiveModel::Validations

    attr_reader :object, :state

    ##
    # Defines the before_transition and after_transition callbacks
    # for use on a HasStateMachine::State instance.
    define_model_callbacks :transition, only: %i[before after]

    ##
    # possible_transitions - Retrieves the next available transitions for a given state.
    # transactional? - Determines whether or not the transition should happen with a transactional block.
    delegate :possible_transitions, :transactional?, :state, to: "self.class"

    ##
    # Initializes the HasStateMachine::State instance.
    #
    # @example
    #   state = Workflow::Post::Draft.new(post) #=> "draft"
    def initialize(object)
      @object = object

      super(state)
    end

    ##
    # Checks to see if the desired state is valid and then gives
    # responsibility to the desired state's instance to make the
    # transition.
    #
    # @param desired_state [String] the state to transition to
    # @param options [Hash] a hash of additional options for
    #   transitioning the object
    #
    # @return [Boolean] whether or not the transition took place
    def transition_to(desired_state, **options)
      transitioned = false

      with_transition_options(options) do
        return false unless valid_transition?(desired_state.to_s)

        desired_state = state_instance(desired_state.to_s)

        transitioned = if desired_state.transactional?
          desired_state.perform_transactional_transition!
        else
          desired_state.perform_transition!
        end
      end

      transitioned
    end

    ##
    # Makes the actual transition from one state to the next and
    # runs the before and after transition callbacks.
    def perform_transition!
      run_callbacks :transition do
        object.update("#{object.state_attribute}": state)
      end
    end

    ##
    # Makes the actual transition from one state to the next and
    # runs the before and after transition callbacks in a transaction
    # to allow for roll backs.
    def perform_transactional_transition!
      ActiveRecord::Base.transaction(requires_new: true, joinable: false) do
        run_callbacks :transition do
          rollback_transition unless object.update("#{object.state_attribute}": state)
        end
      end

      object.reload.public_send(object.state_attribute) == state
    end

    private

    def rollback_transition
      raise ActiveRecord::Rollback
    end

    ##
    # Determines if the given desired state exists in the predetermined
    # list of allowed transitions.
    def can_transition?(desired_state)
      possible_transitions.include? desired_state
    end

    ##
    # Helper method for grabbing the previous state of the object after
    # it has been transitioned to the new state. Useful in
    # after_transition blocks
    def previous_state
      object.previous_changes[object.state_attribute]&.first
    end

    def state_instance(desired_state)
      klass = "#{object.workflow_namespace}::#{desired_state.to_s.classify}".safe_constantize
      klass&.new(object)
    end

    def valid_transition?(desired_state)
      return true if object.skip_state_validations

      object.valid? &&
        can_transition?(desired_state) &&
        state_instance(desired_state)&.valid?
    end

    def with_transition_options(options, &block)
      object.skip_state_validations = options[:skip_validations]
      yield
      object.skip_state_validations = false
    end

    class << self
      def possible_transitions
        @possible_transitions || []
      end

      def state
        to_s.demodulize.underscore
      end

      def transactional?
        @transactional || false
      end

      ##
      # Setter for the HasStateMachine::State classes to define the possible
      # states the current state can transition to.
      def transitions_to(states)
        state_options(transitions_to: states)
        HasStateMachine::Deprecation.deprecation_warning(:transitions_to, "use state_options instead")
      end

      ##
      # Set the options for the HasStateMachine::State classes to define the possible
      # states the current state can transition to and whether or not transitioning
      # to the state should be performed within a transaction.
      def state_options(transitions_to: [], transactional: false)
        @possible_transitions = transitions_to.map(&:to_s)
        @transactional = transactional
      end
    end
  end
end
