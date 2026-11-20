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
        name unless name.empty?
      end

      def workflow_namespace_for(workflow_class_name)
        namespace = workflow_class_name.to_s.delete_prefix("::").rpartition("::").first
        namespace unless namespace.empty?
      end

      def class_name_from_nesting(nesting)
        parts = Array(nesting).map(&:to_s).reject(&:empty?)
        return if parts.empty? || parts.last.start_with?("<Class:")

        # A `::`-anchored segment resets the lexical scope, so outer segments are dropped.
        anchor = parts.rindex { |part| part.start_with?("::") } || 0
        parts[anchor..].join("::").delete_prefix("::")
      end
    end
  end
end
