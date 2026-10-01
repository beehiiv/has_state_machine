# frozen_string_literal: true

require "has_state_machine/deprecation"
require "has_state_machine/machine"
require "has_state_machine/state_helpers"

module HasStateMachine
  class DefinitionBuilder
    OPTION_KEYS = %i[
      state_attribute attribute workflow_namespace state_validations_on_object prefix suffix scopes
    ].freeze

    def initialize(model, states:, **options)
      @model = model
      @states = states
      @options = options.symbolize_keys
    end

    def call
      raise ArgumentError, "Please define at least one state to use has_state_machine." if states.empty?

      @machine = HasStateMachine::Machine.new(states: states, **normalize_options)
      redeclared = register_machine

      model.include HasStateMachine::StateHelpers

      # Preserve 1.x concern/subclass overrides: replace configuration without
      # regenerating methods, defaults, validations, or callbacks.
      model.send(:define_state_machine_methods, machine) unless redeclared
    end

    private

    attr_reader :model, :states, :options, :machine

    # Assign a new registry so subclass declarations cannot mutate the parent's.
    # @return [Boolean] whether an existing definition was replaced
    def register_machine
      unless model.respond_to?(:state_machine_definitions)
        model.class_attribute :state_machine_definitions, instance_accessor: false, instance_predicate: false,
          default: {}.freeze
      end

      existing = model.state_machine_definitions
      replaced = existing.key?(machine.state_attribute)
      others = existing.except(machine.state_attribute)

      ensure_unique_namespace!(others)
      detect_conflicts! if !replaced && others.any?

      model.state_machine_definitions = existing.merge(machine.state_attribute => machine).freeze
      replaced
    end

    def normalize_options
      warn_about_unknown_options

      if options[:state_attribute] && options[:attribute] &&
          options[:state_attribute].to_sym != options[:attribute].to_sym
        HasStateMachine::Deprecation.warn(
          "has_state_machine on #{model} received both state_attribute: #{options[:state_attribute].inspect} " \
          "and attribute: #{options[:attribute].inspect}; attribute: is ignored."
        )
      end

      options[:state_attribute] = (options[:state_attribute] || options[:attribute])&.to_sym || :status
      options.slice(*OPTION_KEYS).except(:attribute)
    end

    def warn_about_unknown_options
      unknown = options.keys - OPTION_KEYS
      return if unknown.empty?

      HasStateMachine::Deprecation.warn(
        "has_state_machine on #{model} received unknown option(s) #{unknown.map(&:inspect).join(", ")}, " \
        "which are ignored. Known options: #{OPTION_KEYS.map(&:inspect).join(", ")}."
      )
    end

    def ensure_unique_namespace!(existing)
      namespace = machine.workflow_namespace_for(model).to_s
      clash = existing.each_value.find { |other| other.workflow_namespace_for(model).to_s == namespace }
      return unless clash

      raise ArgumentError,
        "The state machines on #{clash.state_attribute.inspect} and #{machine.state_attribute.inspect} " \
        "of #{model} would both use the workflow namespace #{namespace.inspect}. " \
        "Pass a distinct workflow_namespace: to has_state_machine."
    end

    # The first machine may override existing methods for 1.x compatibility;
    # additional machines must not overwrite scopes or predicates.
    def detect_conflicts!
      active_record = defined?(ActiveRecord::Base) && model < ActiveRecord::Base

      machine.states.each do |state|
        predicate = machine.predicate_name(state)
        if model.method_defined?(predicate) || model.private_method_defined?(predicate)
          raise_conflict("instance", predicate)
        end

        next unless active_record && machine.scopes?

        scope_name = machine.scope_name(state)
        raise_conflict("class", scope_name) if model.respond_to?(scope_name, true)
      end
    end

    def raise_conflict(type, method_name)
      advice = (type == "class") ? "prefix:, suffix:, or scopes: false" : "prefix: or suffix:"
      raise ArgumentError,
        "has_state_machine #{machine.state_attribute.inspect} on #{model} conflicts with existing " \
        "#{type} method #{method_name.to_s.inspect}. Pass #{advice}."
    end
  end
end
