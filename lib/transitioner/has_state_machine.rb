# frozen_string_literal: true

require "transitioner/state"
require "transitioner/state_helpers"

module Transitioner
  module HasStateMachine
    extend ActiveSupport::Concern

    class_methods do
      ##
      # Configures the state machine for the ActiveRecord object and adds some
      # useful helper methods such as scopes, boolean checks, etc.
      #
      # @param states [Array<Symbol>] the list of possible states in a state machine
      #   @note the first state is used as the initial state
      # @param state_attribute [Symbol] the column name for the attribute holding the current status
      # @param workflow_class [String] the namespace of the models possible states
      #
      # @example
      #   class Post < ApplicationRecord
      #     has_state_machine states: %i(draft published archived)
      #   end
      def has_state_machine(states: [], state_attribute: :status, workflow_class: "Workflow::#{self}")
        raise ArgumentError, "Please define at least one state to use has_state_machine." if states.empty?

        define_helper_methods(states: states.map(&:to_s), state_attribute: state_attribute, workflow_class: workflow_class)

        include Transitioner::StateHelpers
      end

      private

      def define_helper_methods(states:, state_attribute:, workflow_class:)
        ##
        # Defines the column name for the attribute holding the current status.
        # Can be overwritten to use a different column name.
        define_singleton_method "workflow_states" do
          states
        end

        ##
        # Defines the column name for the attribute holding the current status.
        # Can be overwritten to use a different column name.
        define_singleton_method "state_attribute" do
          state_attribute.to_sym
        end

        ##
        # Defines the namespace of the models possible states.
        # Can be overwritten to use a different namespace.
        define_singleton_method "workflow_class" do
          workflow_class.constantize
        end
      end
    end
  end
end
