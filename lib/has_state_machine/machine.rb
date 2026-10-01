# frozen_string_literal: true

module HasStateMachine
  class Machine
    attr_reader :states, :state_attribute, :state_validations_on_object

    alias_method :state_validations_on_object?, :state_validations_on_object

    def initialize(states:, state_attribute: :status, workflow_namespace: nil, state_validations_on_object: true,
      prefix: nil, suffix: nil, scopes: true)
      @states = states.map(&:to_s).freeze
      @state_attribute = state_attribute.to_sym
      @workflow_namespace = workflow_namespace
      @state_validations_on_object = state_validations_on_object
      @prefix = prefix
      @suffix = suffix
      @scopes = scopes
      freeze
    end

    def initial_state
      states.first
    end

    # Resolve defaults against the concrete class so STI subclasses get their own namespace.
    def workflow_namespace_for(model_class)
      @workflow_namespace.presence || "Workflow::#{model_class}"
    end

    def state_class_for(state, model_class)
      return if state.blank?

      "#{workflow_namespace_for(model_class)}::#{state.to_s.classify}".safe_constantize
    end

    def scopes?
      return @scopes_boolean if defined?(@scopes_boolean)

      @scopes_boolean = @scopes != false
    end

    def scope_name(state)
      [method_affix(@prefix), state, method_affix(@suffix)].compact.join("_").to_sym
    end

    def predicate_name(state)
      :"#{scope_name(state)}?"
    end

    private

    def method_affix(value)
      return unless value
      return state_attribute if value == true

      value
    end
  end
end
