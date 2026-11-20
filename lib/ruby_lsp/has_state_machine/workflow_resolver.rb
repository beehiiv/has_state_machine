# frozen_string_literal: true

module RubyLsp
  module HasStateMachine
    module WorkflowResolver
      WORKFLOW_PREFIX = "Workflow::"

      module_function

      def model_name_for(workflow_class_name)
        namespace = workflow_namespace_for(workflow_class_name)
        return unless namespace&.start_with?(WORKFLOW_PREFIX)

        name = namespace.delete_prefix(WORKFLOW_PREFIX)
        return if name.empty?

        name
      end

      def workflow_namespace_for(workflow_class_name)
        name = workflow_class_name.to_s.delete_prefix("::")
        return unless name.include?("::")

        namespace = name.sub(/::[^:]+\z/, "")
        return if namespace.empty?

        namespace
      end

      def class_name_from_nesting(nesting)
        parts = Array(nesting).map(&:to_s).reject(&:empty?)
        return if parts.empty? || parts.last.start_with?("<Class:")

        resolved = []
        parts.reverse_each do |part|
          resolved.unshift(part.delete_prefix("::"))
          break if part.start_with?("::")
        end

        name = resolved.join("::").gsub(/:{3,}/, "::")
        name unless name.empty?
      end
    end
  end
end
