# frozen_string_literal: true

require "active_support/core_ext/string"

module Transitioner
  class State < String
    extend ActiveModel::Model
    extend ActiveModel::Callbacks
    include ActiveModel::Validations

    attr_reader :object, :state, :options

    ##
    # Defines the before_transition and after_transition callbacks
    # for use on a Transitioner::State instance.
    define_model_callbacks :transition, only: %i[before after]

    ##
    # Retrieves the next available transitions for a given state.
    delegate :possible_transitions, to: "self.class"

    ##
    # Add errors to the ActiveRecord object rather than the Transitioner::State
    # class.
    delegate :errors, to: :object

    ##
    # Initializes the Transitioner::State instance.
    #
    # @example
    #   state = Transitioner::State.new(post) #=> "draft"
    #   state.class #=> Workflow::Post::Draft
    def initialize(object, state)
      @object = object
      @state = state
      super @state
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
      with_transition_options(options) do
        return false unless valid_transition?(desired_state.to_s)

        state_instance(desired_state.to_s).perform_transition!
      end
    end

    ##
    # Makes the actual transition from one state to the next and
    # runs the before and after transition callbacks.
    def perform_transition!
      run_callbacks :transition do
        object.update("#{object.state_attribute}": state)
      end
    end

    private

    ##
    # Determines if the given desired state exists in the predetermined
    # list of allowed transitions.
    def can_transition?(desired_state)
      possible_transitions.include? desired_state
    end

    def state_instance(desired_state)
      klass = "#{object.workflow_namespace}::#{desired_state.to_s.classify}".safe_constantize
      klass&.new(object, desired_state)
    end

    def valid_transition?(desired_state)
      return true if options[:skip_validations]

      object.valid? &&
        can_transition?(desired_state) &&
        state_instance(desired_state)&.valid?
    end

    def with_transition_options(options, &block)
      @options = options
      object.skip_state_validations = options[:skip_validations]
      yield
      object.skip_state_validations = false
    end

    class << self
      def possible_transitions
        @possible_transitions || []
      end

      ##
      # Setter for the Transitioner::State classes to define the possible
      # states the current state can transition to.
      def transitions_to(states)
        @possible_transitions = states.map(&:to_s)
      end
    end
  end
end
