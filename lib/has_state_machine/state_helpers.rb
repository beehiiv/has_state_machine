# frozen_string_literal: true

module HasStateMachine
  # Shared model helpers and per-machine method generation.
  module StateHelpers
    extend ActiveSupport::Concern

    included do
      # Skips state-instance validations for every machine on this object.
      attr_accessor :skip_state_validations

      delegate \
        :state_attribute,
        :state_validations_on_object?,
        :workflow_namespace,
        :workflow_states,
        to: :class
    end

    private

    # Resolve at call time so redeclarations take effect.
    def state_machine_definition_for(attr)
      self.class.state_machine_definitions.fetch(attr)
    end

    # Default to the primary machine for 1.x compatibility.
    def current_state(machine = self.class.primary_state_machine_definition)
      self[machine.state_attribute]
    end

    def state_class(machine = self.class.primary_state_machine_definition)
      machine.state_class_for(current_state(machine), self.class)
    end

    def state_class_defined?(machine = self.class.primary_state_machine_definition)
      return if state_class(machine)

      errors.add(machine.state_attribute, :not_implemented, message: "class must be implemented")
    end

    def should_validate_state?(machine = self.class.primary_state_machine_definition)
      return false unless machine.state_validations_on_object?

      !skip_state_validations
    end

    def state_instance_validations(machine = self.class.primary_state_machine_definition)
      return unless state_class(machine)

      current_state_instance = public_send(machine.state_attribute)
      return if current_state_instance.valid?

      current_state_instance.errors.each do |error|
        errors.add(error.attribute, error.type)
      end
    end

    class_methods do
      delegate :state_attribute, :state_validations_on_object?, to: :primary_state_machine_definition

      def workflow_states
        primary_state_machine_definition.states
      end

      def workflow_namespace
        primary_state_machine_definition.workflow_namespace_for(self)
      end

      # First declaration, including inherited machines.
      # @return [HasStateMachine::Machine]
      def primary_state_machine_definition
        state_machine_definitions.each_value.first
      end

      private

      def define_state_machine_methods(machine)
        attr = machine.state_attribute

        attribute attr, :string, default: machine.initial_state

        validates attr, inclusion: {in: machine.states}, presence: true

        if machine.equal?(primary_state_machine_definition)
          validate :state_class_defined?
          validate :state_instance_validations, if: :should_validate_state?
        else
          validate { state_class_defined?(state_machine_definition_for(attr)) }
          validate(if: -> { should_validate_state?(state_machine_definition_for(attr)) }) do
            state_instance_validations(state_machine_definition_for(attr))
          end
        end

        # Return the raw value when no state class exists.
        define_method attr do
          current_machine = state_machine_definition_for(attr)
          klass = state_class(current_machine)
          return klass.new(self).bind_state_machine(current_machine) if klass

          current_state(current_machine)
        end

        machine.states.each do |state|
          if machine.scopes? && defined?(ActiveRecord) && (self < ActiveRecord::Base)
            scope machine.scope_name(state), -> { where(attr => state) }
          end

          define_method machine.predicate_name(state) do
            self[attr] == state
          end
        end
      end
    end
  end
end
