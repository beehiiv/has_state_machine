# frozen_string_literal: true

module RubyLsp
  module HasStateMachine
    class NamespaceRegistry
      class << self
        def instance
          @instance ||= new
        end

        def clear
          instance.clear
        end
      end

      def initialize
        @mutex = Mutex.new
        @by_uri = {}
        @by_namespace = {}
      end

      def clear_uri(uri)
        key = uri.to_s
        @mutex.synchronize do
          remove_uri_entries(key)
        end
      end

      def register(uri:, workflow_namespace:, model_name:)
        uri_key = uri.to_s
        namespace = workflow_namespace.to_s.delete_prefix("::")
        model = model_name.to_s.delete_prefix("::")
        return if namespace.empty? || model.empty?

        @mutex.synchronize do
          (@by_uri[uri_key] ||= []) << [namespace, model]
          @by_namespace[namespace] = model
        end
      end

      def model_for(workflow_namespace)
        namespace = workflow_namespace.to_s.delete_prefix("::")
        return if namespace.empty?

        @mutex.synchronize do
          @by_namespace[namespace]
        end
      end

      def key?(workflow_namespace)
        !model_for(workflow_namespace).nil?
      end

      def clear
        @mutex.synchronize do
          @by_uri.clear
          @by_namespace.clear
        end
      end

      private

      def remove_uri_entries(uri_key)
        removed = @by_uri.delete(uri_key)
        return unless removed

        removed.each do |namespace, model|
          next unless @by_namespace[namespace] == model

          replacement = find_model_for_namespace(namespace)
          if replacement
            @by_namespace[namespace] = replacement
          else
            @by_namespace.delete(namespace)
          end
        end
      end

      def find_model_for_namespace(namespace)
        @by_uri.each_value do |pairs|
          pair = pairs.find { |ns, _model| ns == namespace }
          return pair.last if pair
        end

        nil
      end
    end
  end
end
