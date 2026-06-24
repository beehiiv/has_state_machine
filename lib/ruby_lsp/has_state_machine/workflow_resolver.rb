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
        namespace = workflow_class_name.to_s.delete_prefix("::").sub(/::[^:]+\z/, "")
        return if namespace.empty?

        namespace
      end
    end
  end
end
