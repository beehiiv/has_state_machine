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
      # @param opts [Hash] a hash of additional options for the state machine
      #
      # @example
      #   class Post < ApplicationRecord
      #     has_state_machine states: %i(draft published archived)
      #   end
      def has_state_machine(states: [], **options)
        raise ArgumentError, "Please define at least one state to use has_state_machine." if states.empty?

        define_helper_methods(
          states: states.map(&:to_s),
          options: options.with_indifferent_access
        )

        include Transitioner::StateHelpers
      end

      private

      def define_helper_methods(states:, options:)
        ##
        # The list of possible states in the state machine.
        # Can be overwritten to use a different column name.
        define_singleton_method "workflow_states" do
          states
        end

        ##
        # Defines the column name for the attribute holding the current status.
        # Can be overwritten to use a different column name.
        define_singleton_method "state_attribute" do
          options[:state_attribute]&.to_sym || :status
        end

        ##
        # Defines the namespace of the models possible states.
        # Can be overwritten to use a different namespace.
        define_singleton_method "workflow_namespace" do
          (options[:workflow_namespace] || "Workflow::#{self}").constantize
        end

        ##
        # Determines whether or not the state validations should be run
        # as part of the object validations.
        define_singleton_method "state_validations_on_object?" do
          return true unless options.key?(:state_validations_on_object)

          options[:state_validations_on_object]
        end
      end
    end
  end
end
