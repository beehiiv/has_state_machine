# frozen_string_literal: true

module HasStateMachine
  class Machine
    attr_reader :states, :state_attribute, :state_validations_on_object

    alias_method :state_validations_on_object?, :state_validations_on_object

    def initialize(states:, state_attribute:, workflow_namespace:, state_validations_on_object:, prefix:, scopes:)
      @states = states.map(&:to_s).freeze
      @state_attribute = state_attribute.to_sym
      @workflow_namespace = workflow_namespace
      @state_validations_on_object = state_validations_on_object
      @prefix = prefix
      @scopes = scopes
      freeze
    end

    def initial_state
      states.first
    end

    # Resolve defaults against the concrete class so STI subclasses get their own namespace.
    def workflow_namespace_for(model_class)
      @workflow_namespace || "Workflow::#{model_class}"
    end

    # Returns nil for a blank state or missing class.
    def state_class_for(state, model_class)
      return if state.blank?

      "#{workflow_namespace_for(model_class)}::#{state.to_s.classify}".safe_constantize
    end

    def scopes?
      @scopes != false
    end

    def scope_name(state)
      :"#{method_prefix}#{state}"
    end

    def predicate_name(state)
      :"#{scope_name(state)}?"
    end

    private

    def method_prefix
      case @prefix
      when nil, false then ""
      when true then "#{state_attribute}_"
      else "#{@prefix}_"
      end
    end
  end
end
