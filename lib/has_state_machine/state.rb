# frozen_string_literal: true

require "active_support/core_ext/string"

module HasStateMachine
  class State < String
    extend ActiveModel::Model
    extend ActiveModel::Callbacks
    include ActiveModel::Validations

    attr_reader :object

    define_model_callbacks :transition, only: %i[before after]

    define_model_callbacks :transition_commit, only: %i[after]

    delegate :possible_transitions, :transactional?, :state, :transients, to: :class

    # @example
    #   Workflow::Post::Draft.new(post) #=> "draft"
    def initialize(object, transient_values = {})
      @object = object

      transient_values.to_h.slice(*transients).each do |transient, value|
        instance_variable_set(:"@#{transient}", value)
      end

      super(state)
    end

    # Bound by the model getter; direct instances resolve by namespace,
    # falling back to the primary machine.
    #
    # @return [HasStateMachine::Machine, nil]
    def state_machine
      return @state_machine if @state_machine

      model_class = object.class
      definitions = model_class.try(:state_machine_definitions)
      return unless definitions

      machines = definitions.each_value
      namespace = self.class.name&.deconstantize

      @state_machine = machines.find do |machine|
        machine.workflow_namespace_for(model_class).to_s == namespace
      end || machines.first
    end

    # @return [Symbol]
    def state_attribute
      state_machine&.state_attribute || object.state_attribute
    end

    # @api private
    def bind_state_machine(machine)
      @state_machine = machine
      self
    end

    # Checks the allowed transition list without running validations.
    # @param desired_state [String, Symbol]
    def can_transition?(desired_state)
      possible_transitions.include? desired_state.to_s
    end

    # Validates and transitions to the target state, copying its errors to the model.
    #
    # @param desired_state [String, Symbol]
    # @param options [Hash] target-state transients and transition options
    # @option options [Boolean] :skip_validations (false) bypass transition checks and state validations
    # @return [Boolean] whether the transition succeeded
    def transition_to(desired_state, **options)
      transitioned = false
      options = options.symbolize_keys
      desired_state_instance = state_instance(desired_state, options)

      with_transition_options(options) do
        return false unless valid_transition?(desired_state_instance)

        transitioned = if desired_state_instance.transactional?
          desired_state_instance.perform_transactional_transition!
        else
          desired_state_instance.perform_transition!
        end
      end

      transitioned
    ensure
      desired_state_instance&.errors&.each do |error|
        object.errors.add(error.attribute, error.type)
      end
    end

    # Persists the target state and runs transition callbacks.
    # @return [Boolean] whether the transition succeeded
    def perform_transition! # rubocop:disable Naming/PredicateMethod -- public API
      transitioned = run_callbacks :transition do
        update_state_attribute
      end

      return false unless transitioned

      enqueue_transition_commit_callbacks
      true
    end

    # Wraps the transition in a transaction that callbacks can roll back.
    # @return [Boolean] whether the transition succeeded
    def perform_transactional_transition! # rubocop:disable Naming/PredicateMethod -- public API
      ActiveRecord::Base.transaction(requires_new: true, joinable: false) do
        run_callbacks :transition do
          rollback_transition unless update_state_attribute
        end
      end

      return false unless object.reload.public_send(state_attribute) == state

      enqueue_transition_commit_callbacks
      true
    end

    private

    # Capture the previous state before transition callbacks can save the model again.
    def update_state_attribute # rubocop:disable Naming/PredicateMethod -- returns update's result
      return false unless object.update(state_attribute => state)

      @previous_state = previous_state
      true
    end

    # Use the current transaction: after_all_transactions_commit ignores our
    # non-joinable transactions and would run callbacks before commit.
    def enqueue_transition_commit_callbacks
      current_transaction = object.class.connection.current_transaction

      # Rails < 7.2 has no Transaction#after_commit; run callbacks immediately.
      return run_callbacks(:transition_commit) { true } unless current_transaction.respond_to?(:after_commit)

      current_transaction.after_commit { run_callbacks(:transition_commit) { true } }
    end

    def rollback_transition
      raise ActiveRecord::Rollback
    end

    # Available in after_transition and after_transition_commit callbacks.
    def previous_state
      @previous_state.presence || object.previous_changes[state_attribute]&.first
    end

    def state_instance(desired_state, transient_values)
      klass = if state_machine
        state_machine.state_class_for(desired_state, object.class)
      else
        "#{object.workflow_namespace}::#{desired_state.to_s.classify}".safe_constantize
      end
      klass&.new(object, transient_values)&.bind_state_machine(state_machine)
    end

    def valid_transition?(desired_state_instance)
      return true if object.skip_state_validations

      object.valid? &&
        can_transition?(desired_state_instance) &&
        desired_state_instance&.valid?
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

      def transients
        @transients || []
      end

      # transitions_to applies when leaving this state; transactional and transients apply when entering it.
      def state_options(transitions_to: [], transactional: false, transients: [])
        @possible_transitions = transitions_to.map(&:to_s)
        @transactional = transactional
        @transients = transients.map(&:to_sym)

        attr_reader(*@transients)
      end
    end
  end
end
