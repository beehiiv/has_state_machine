# frozen_string_literal: true

require "has_state_machine/definition_builder"
require "has_state_machine/state"
require "has_state_machine/state_helpers"

module HasStateMachine
  module Definition
    extend ActiveSupport::Concern

    class_methods do
      # Declares one machine per state attribute. The first machine is primary
      # for the class and instance readers. Unknown options warn and are ignored.
      #
      # @param states [Array<String, Symbol>] allowed states; the first is the default
      # @param options [Hash]
      # @option options [String, Symbol] :state_attribute (:status) state column
      # @option options [String, Symbol] :attribute alias for :state_attribute
      # @option options [String] :workflow_namespace ("Workflow::<Model>") state-class namespace; unique per model
      # @option options [Boolean] :state_validations_on_object (true) run state validations on the model
      # @option options [Boolean, String, Symbol] :prefix scope/predicate prefix; true uses the state attribute
      # @option options [Boolean, String, Symbol] :suffix scope/predicate suffix; true uses the state attribute
      # @option options [Boolean] :scopes (true) generate scopes
      #
      # @example
      #   class Post < ApplicationRecord
      #     has_state_machine states: %i(draft published archived)
      #     has_state_machine states: %i(available removing),
      #       state_attribute: :deletion_state,
      #       workflow_namespace: "Workflow::PostDeletion",
      #       prefix: :deletion
      #   end
      def has_state_machine(states: [], **options)
        HasStateMachine::DefinitionBuilder.new(self, states: states, **options).call
      end
    end
  end
end
