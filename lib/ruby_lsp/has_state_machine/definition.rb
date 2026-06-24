# frozen_string_literal: true

require_relative "workflow_resolver"

module RubyLsp
  module HasStateMachine
    class Definition
      SERVER_ADDON_NAME = "has_state_machine"

      def initialize(response_builder, _uri, node_context, dispatcher, index: nil, rails_client: nil)
        @response_builder = response_builder
        @node_context = node_context
        @index = index
        @rails_client = rails_client

        dispatcher.register(self, :on_call_node_enter)
      end

      def on_call_node_enter(node)
        return unless current_target?(node)
        return unless resolved_model_name

        if object_call?(node)
          push_entries(constant_entries(resolved_model_name))
        elsif object_method_call?(node)
          method_name = message(node)
          entries = method_entries(resolved_model_name, method_name)
          entries = association_entries(resolved_model_name, method_name) if entries.empty?

          push_entries(entries)
        end
      end

      private

      attr_reader :index, :node_context, :rails_client, :response_builder

      def current_target?(node)
        target = node_context.node if node_context.respond_to?(:node)
        call_node = node_context.call_node if node_context.respond_to?(:call_node)

        node.equal?(target) || node.equal?(call_node)
      end

      def resolved_model_name
        return @resolved_model_name if defined?(@resolved_model_name)
        return @resolved_model_name = nil unless current_class_name

        @resolved_model_name = if convention_model_name && constant_entries(convention_model_name).any?
          convention_model_name
        else
          model_name_from_rails(workflow_namespace) || convention_model_name
        end
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

        @current_class_name = class_name_from_nesting(node_context.nesting)
      end

      def class_name_from_nesting(nesting)
        parts = nesting.map(&:to_s).reject(&:empty?)
        return if parts.empty?

        # Nesting entries may already contain "::" (e.g. "Post::Draft").
        parts.join("::").gsub(/:{3,}/, "::")
      end

      def model_name_from_rails(workflow_namespace)
        return unless workflow_namespace && rails_client

        result = rails_client.delegate_request(
          server_addon_name: SERVER_ADDON_NAME,
          request_name: "model_for_workflow_namespace",
          workflow_namespace: workflow_namespace
        )

        response_name(result)
      rescue
        nil
      end

      def association_entries(model_name, association_name)
        association_model_name = association_model_name(model_name, association_name)
        return [] unless association_model_name

        constant_entries(association_model_name)
      end

      def association_model_name(model_name, association_name)
        return unless rails_client&.respond_to?(:association_target)

        result = rails_client.association_target(model_name: model_name, association_name: association_name)
        response_name(result)
      rescue
        nil
      end

      def response_name(result)
        return unless result

        result[:name] || result["name"]
      end

      def constant_entries(name)
        return [] unless name && index

        Array(index[name])
      end

      def method_entries(model_name, method_name)
        return [] unless index && method_name

        if index.respond_to?(:resolve_method)
          entries = index.resolve_method(method_name, model_name)
          return Array(entries)
        end

        Array(index[method_name]).select { |entry| entry_owner_name(entry) == model_name }
      end

      def entry_owner_name(entry)
        owner = entry.owner if entry.respond_to?(:owner)
        owner.name if owner.respond_to?(:name)
      end

      def push_entries(entries)
        entries.each do |entry|
          response_builder << location_for(entry)
        end
      end

      def location_for(entry)
        return entry unless defined?(::RubyLsp::Interface::Location)

        location = entry_location(entry)
        return entry unless location

        ::RubyLsp::Interface::Location.new(
          uri: entry.uri.to_s,
          range: range_for(location)
        )
      end

      def entry_location(entry)
        return entry.location if entry.respond_to?(:location)
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
        message(node) && object_call?(receiver(node))
      end

      def object_call?(node)
        node && receiver(node).nil? && message(node) == "object"
      end

      def receiver(node)
        node.receiver if node.respond_to?(:receiver)
      end

      def message(node)
        node.message.to_s if node.respond_to?(:message) && node.message
      end
    end
  end
end
