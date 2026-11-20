# frozen_string_literal: true

require_relative "namespace_registry"

module RubyLsp
  module HasStateMachine
    class IndexingEnhancement < ::RubyIndexer::Enhancement
      def on_call_node_enter(call_node)
        return unless call_node.name == :has_state_machine
        return unless call_node.receiver.nil? || call_node.receiver.is_a?(::Prism::SelfNode)

        owner = @listener.current_owner
        return unless owner

        # Ruby LSP builds a fresh enhancement per indexed file, so this clears each URI once per pass.
        @uri_cleared ||= NamespaceRegistry.instance.clear_uri(owner.uri) || true

        options = extract_options(call_node)
        state_attr, attr_location = extract_state_attribute(options, call_node)

        add_reader(state_attr, attr_location)
        register_workflow_namespace(owner, options["workflow_namespace"])
        index_state_predicates(options, state_attr)
      end

      private

      def extract_options(call_node)
        arguments = call_node.arguments&.arguments
        return {} unless arguments

        arguments
          .select { |argument| argument.is_a?(::Prism::KeywordHashNode) || argument.is_a?(::Prism::HashNode) }
          .flat_map(&:elements)
          .grep(::Prism::AssocNode)
          .filter_map { |assoc| (key = extract_string_or_symbol(assoc.key)) && [key, assoc.value] }
          .to_h
      end

      def extract_state_attribute(options, call_node)
        node = options["state_attribute"] || options["attribute"]
        name = extract_string_or_symbol(node)
        return ["status", call_node.location] if name.to_s.empty?

        [name, node.location]
      end

      def register_workflow_namespace(owner, namespace_node)
        return unless owner.is_a?(::RubyIndexer::Entry::Class)

        namespace = extract_namespace(namespace_node)
        return if namespace.to_s.strip.empty?

        NamespaceRegistry.instance.register(
          uri: owner.uri,
          workflow_namespace: namespace,
          model_name: owner.name
        )
      end

      def index_state_predicates(options, state_attr)
        elements = literal_states(options["states"])
        return if elements.empty?

        prefix = extract_affix(options["prefix"], state_attr)
        suffix = extract_affix(options["suffix"], state_attr)
        return if [prefix, suffix].include?(:dynamic)

        elements.each do |element|
          state_name = extract_string_or_symbol(element)
          next if state_name.to_s.empty?

          predicate = "#{[prefix, state_name, suffix].compact.join("_")}?"
          add_reader(predicate, element.location)
        end
      end

      def literal_states(node)
        node = node.receiver if node.is_a?(::Prism::CallNode) && node.name == :freeze
        node.is_a?(::Prism::ArrayNode) ? node.elements : []
      end

      def extract_affix(node, state_attr)
        case node
        when nil, ::Prism::FalseNode, ::Prism::NilNode then nil
        when ::Prism::TrueNode then state_attr
        else
          value = extract_string_or_symbol(node)
          value.to_s.empty? ? :dynamic : value
        end
      end

      def extract_namespace(node)
        case node
        when ::Prism::StringNode, ::Prism::SymbolNode
          node.unescaped
        when ::Prism::ConstantReadNode, ::Prism::ConstantPathNode
          ::RubyIndexer::Index.constant_name(node)
        end
      end

      def extract_string_or_symbol(node)
        case node
        when ::Prism::StringNode, ::Prism::SymbolNode
          node.unescaped
        end
      end

      def add_reader(name, location)
        @listener.add_method(name, location, [::RubyIndexer::Entry::Signature.new([])])
      end
    end
  end
end
