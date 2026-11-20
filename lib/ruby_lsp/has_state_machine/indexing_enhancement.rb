# frozen_string_literal: true

require_relative "namespace_registry"

if defined?(::RubyIndexer::Enhancement)
  module RubyLsp
    module HasStateMachine
      class IndexingEnhancement < ::RubyIndexer::Enhancement
        def on_call_node_enter(call_node)
          return unless call_node.name == :has_state_machine
          return unless call_node.receiver.nil? || call_node.receiver.is_a?(::Prism::SelfNode)

          owner = @listener.current_owner
          return unless owner

          clear_uri_once(owner.uri)

          options = extract_options(call_node)
          state_attr, attr_location = extract_state_attribute(options, call_node)

          add_reader(state_attr, attr_location)
          register_workflow_namespace(owner, options["workflow_namespace"])
          index_state_predicates(options, state_attr)
        end

        private

        def clear_uri_once(uri)
          uri_key = uri.to_s
          @cleared_uris ||= {}
          return if @cleared_uris[uri_key]

          @cleared_uris[uri_key] = true
          NamespaceRegistry.instance.clear_uri(uri_key)
        end

        def extract_options(call_node)
          arguments = call_node.arguments&.arguments
          return {} unless arguments

          options = {}
          arguments.each do |argument|
            next unless argument.is_a?(::Prism::KeywordHashNode) || argument.is_a?(::Prism::HashNode)

            argument.elements.each do |element|
              next unless element.is_a?(::Prism::AssocNode)

              key = extract_string_or_symbol(element.key)
              options[key] = element.value if key
            end
          end
          options
        end

        def extract_state_attribute(options, call_node)
          node = options["state_attribute"] || options["attribute"]
          name = extract_string_or_symbol(node)
          if name && !name.empty?
            [name, node.location]
          else
            ["status", call_node.location]
          end
        end

        def register_workflow_namespace(owner, namespace_node)
          return unless owner.is_a?(::RubyIndexer::Entry::Class)

          namespace = extract_namespace(namespace_node)
          return if namespace.nil? || namespace.strip.empty?

          NamespaceRegistry.instance.register(
            uri: owner.uri,
            workflow_namespace: namespace,
            model_name: owner.name
          )
        end

        def index_state_predicates(options, state_attr)
          elements = extract_literal_states(options["states"])
          return if elements.empty?

          prefix = extract_affix(options["prefix"], state_attr)
          return if prefix == :dynamic

          suffix = extract_affix(options["suffix"], state_attr)
          return if suffix == :dynamic

          elements.each do |element|
            state_name = extract_string_or_symbol(element)
            next if state_name.nil? || state_name.empty?

            predicate = "#{[prefix, state_name, suffix].compact.join("_")}?"
            add_reader(predicate, element.location)
          end
        end

        def extract_literal_states(states_node)
          array_node = unwrap_array_node(states_node)
          return [] unless array_node

          array_node.elements
        end

        def unwrap_array_node(node)
          return node if node.is_a?(::Prism::ArrayNode)

          if node.is_a?(::Prism::CallNode) && node.name == :freeze && node.receiver.is_a?(::Prism::ArrayNode)
            return node.receiver
          end

          nil
        end

        def extract_affix(node, state_attr)
          return nil if node.nil? || node.is_a?(::Prism::FalseNode) || node.is_a?(::Prism::NilNode)
          return state_attr if node.is_a?(::Prism::TrueNode)

          value = extract_string_or_symbol(node)
          return value if value && !value.empty?

          :dynamic
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
end
