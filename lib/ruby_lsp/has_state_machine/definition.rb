# frozen_string_literal: true

require_relative "index_adapter"
require_relative "namespace_registry"
require_relative "workflow_resolver"

module RubyLsp
  module HasStateMachine
    class Definition
      STATE_SUPERCLASS = "HasStateMachine::State"

      # ActiveRecord methods that return self, so `object.reload.foo` targets the model
      # just like `object.foo`.
      SELF_RETURNING_METHODS = %w[reload lock!].freeze

      def initialize(response_builder, _uri, node_context, dispatcher, index: nil,
        namespace_registry: NamespaceRegistry.instance)
        @response_builder = response_builder
        @node_context = node_context
        @index = IndexAdapter.new(index)
        @namespace_registry = namespace_registry

        dispatcher.register(self, :on_call_node_enter)
      end

      def on_call_node_enter(node)
        return unless current_target?(node)

        is_object_call = object_call?(node)
        is_object_method = !is_object_call && object_method_call?(node)
        return unless is_object_call || is_object_method
        return unless workflow_state_class?

        model_name = resolved_model_name
        return unless model_name

        entries = if is_object_call
          index.class_entries(model_name)
        else
          resolve_object_method_entries(model_name, node)
        end
        return if entries.empty?

        replace_response_entries(entries)
      end

      private

      attr_reader :index, :namespace_registry, :node_context, :response_builder

      def current_target?(node)
        target = node_context.node if node_context.respond_to?(:node)
        call_node = node_context.call_node if node_context.respond_to?(:call_node)

        node.equal?(target) || node.equal?(call_node)
      end

      def workflow_state_class?
        return false unless current_class_name

        if index.ready_for_ancestry?(STATE_SUPERCLASS)
          ancestors = index.ancestors_of(current_class_name)
          return ancestors.include?(STATE_SUPERCLASS) if ancestors
        end

        workflow_namespace_known?
      end

      def workflow_namespace_known?
        return false unless workflow_namespace

        namespace_registry&.key?(workflow_namespace) ||
          workflow_namespace.start_with?(WorkflowResolver::WORKFLOW_PREFIX)
      end

      def resolved_model_name
        return @resolved_model_name if defined?(@resolved_model_name)
        return @resolved_model_name = nil unless current_class_name

        candidate = namespace_registry&.model_for(workflow_namespace) || convention_model_name
        @resolved_model_name = candidate if candidate && !index.class_entries(candidate).empty?
      end

      def convention_model_name
        return @convention_model_name if defined?(@convention_model_name)

        @convention_model_name = current_class_name && WorkflowResolver.model_name_for(current_class_name)
      end

      def workflow_namespace
        return @workflow_namespace if defined?(@workflow_namespace)

        @workflow_namespace = current_class_name && WorkflowResolver.workflow_namespace_for(current_class_name)
      end

      def current_class_name
        return @current_class_name if defined?(@current_class_name)
        return @current_class_name = nil unless node_context.respond_to?(:nesting)

        @current_class_name = WorkflowResolver.class_name_from_nesting(node_context.nesting)
      end

      def resolve_object_method_entries(model_name, node)
        primary_name = call_name(node)
        fallback_name = message(node)

        entries = index.method_entries(model_name, primary_name)
        if entries.empty? && fallback_name && fallback_name != primary_name
          entries = index.method_entries(model_name, fallback_name)
        end
        entries = index.class_entries(model_name) if entries.empty?
        entries
      end

      # Listeners::Definition runs first and pushes State#object or guessed Object
      # fallbacks as LocationLink. Clearing them avoids both noisy pickers and mixed
      # Location/LocationLink arrays that fail LSP deserialization in strict clients.
      def replace_response_entries(entries)
        if response_builder.respond_to?(:response) && response_builder.response.is_a?(Array)
          response_builder.response.clear
        end

        entries.each do |entry|
          response_builder << location_for(entry)
        end
      end

      def location_for(entry)
        location = entry_location(entry)
        return entry unless location

        if defined?(::RubyLsp::Interface::LocationLink)
          selection = entry_selection_location(entry) || location
          return ::RubyLsp::Interface::LocationLink.new(
            target_uri: entry.uri.to_s,
            target_range: range_for(location),
            target_selection_range: range_for(selection)
          )
        end

        return entry unless defined?(::RubyLsp::Interface::Location)

        ::RubyLsp::Interface::Location.new(
          uri: entry.uri.to_s,
          range: range_for(location)
        )
      end

      def entry_location(entry)
        return entry.location if entry.respond_to?(:location)

        entry.name_location if entry.respond_to?(:name_location)
      end

      def entry_selection_location(entry)
        entry.name_location if entry.respond_to?(:name_location)
      end

      def range_for(location)
        ::RubyLsp::Interface::Range.new(
          start: ::RubyLsp::Interface::Position.new(
            line: location.start_line - 1,
            character: location.start_column
          ),
          end: ::RubyLsp::Interface::Position.new(
            line: location.end_line - 1,
            character: location.end_column
          )
        )
      end

      def object_method_call?(node)
        message(node) && object_chain?(receiver(node))
      end

      def object_chain?(node)
        return false unless node
        return true if object_call?(node)

        SELF_RETURNING_METHODS.include?(message(node)) && object_chain?(receiver(node))
      end

      def object_call?(node)
        node && self_receiver?(node) && message(node) == "object"
      end

      def self_receiver?(node)
        recv = receiver(node)
        recv.nil? || (defined?(::Prism::SelfNode) && recv.is_a?(::Prism::SelfNode))
      end

      def receiver(node)
        node.receiver if node.respond_to?(:receiver)
      end

      def call_name(node)
        return node.name.to_s if node.respond_to?(:name) && node.name

        message(node)
      end

      def message(node)
        node.message.to_s if node.respond_to?(:message) && node.message
      end
    end
  end
end
