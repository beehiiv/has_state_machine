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

        return if model_entries.empty?

        replace_response_entries(is_object_call ? model_entries : resolve_object_method_entries(node))
      end

      private

      attr_reader :index, :namespace_registry, :node_context, :response_builder

      def current_target?(node)
        node.equal?(node_context.node) || node.equal?(node_context.call_node)
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

        namespace_registry.model_for(workflow_namespace) ||
          workflow_namespace.start_with?(WorkflowResolver::WORKFLOW_PREFIX)
      end

      def model_name
        return @model_name if defined?(@model_name)

        @model_name = namespace_registry.model_for(workflow_namespace) || convention_model_name
      end

      def model_entries
        @model_entries ||= index.class_entries(model_name)
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

        @current_class_name = WorkflowResolver.class_name_from_nesting(node_context.nesting)
      end

      # Setters resolve by `name` (`title=`), falling back to the reader (`title`) when only that is indexed.
      def resolve_object_method_entries(node)
        [call_name(node), message(node)].uniq.each do |method_name|
          entries = index.method_entries(model_name, method_name)
          return entries unless entries.empty?
        end

        model_entries
      end

      # Ruby LSP's own definition listener runs first and pushes State#object and same-name
      # guesses. Replacing them keeps the picker to the model and avoids mixing Location with
      # LocationLink, which strict clients fail to deserialize.
      def replace_response_entries(entries)
        response_builder.response.clear if response_builder.respond_to?(:response)

        entries.each do |entry|
          response_builder << location_for(entry)
        end
      end

      def location_for(entry)
        # Only namespace and method entries carry a name_location.
        selection = (entry.name_location if entry.respond_to?(:name_location)) || entry.location
        ::RubyLsp::Interface::LocationLink.new(
          target_uri: entry.uri.to_s,
          target_range: range_for(entry.location),
          target_selection_range: range_for(selection)
        )
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
        recv.nil? || recv.is_a?(::Prism::SelfNode)
      end

      def receiver(node)
        node.receiver if node.respond_to?(:receiver)
      end

      def call_name(node)
        node.name&.to_s || message(node)
      end

      def message(node)
        node.message.to_s if node.respond_to?(:message) && node.message
      end
    end
  end
end
