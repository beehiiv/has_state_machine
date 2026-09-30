# frozen_string_literal: true

require "ruby_lsp/ruby_lsp_rails/server" unless defined?(::RubyLsp::Rails::ServerAddon)

module RubyLsp
  module HasStateMachine
    class RailsServerAddon < ::RubyLsp::Rails::ServerAddon
      def name
        "has_state_machine"
      end

      def execute(request, params)
        with_request_error_handling(request) do
          case request
          when "model_for_workflow_namespace"
            send_result(model_for_workflow_namespace(params[:workflow_namespace] || params.fetch("workflow_namespace")))
          else
            raise NotImplementedError, "Unknown request: #{request}"
          end
        end
      end

      private

      def model_for_workflow_namespace(workflow_namespace)
        model = conventional_model_for(workflow_namespace) || models_by_workflow_namespace[workflow_namespace]
        return unless model

        {name: model.name}
      end

      # Resolve conventional namespaces without eager-loading the application.
      def conventional_model_for(workflow_namespace)
        workflow_namespace = workflow_namespace.to_s
        return unless workflow_namespace.start_with?("Workflow::")

        model = workflow_namespace.delete_prefix("Workflow::").safe_constantize
        model if model.try(:workflow_namespace) == workflow_namespace
      end

      def models_by_workflow_namespace
        @models_by_workflow_namespace ||= active_record_models.each_with_object({}) do |model, index|
          workflow_namespaces_for(model).each { |namespace| index[namespace] = model }
        end
      end

      # Keep inherited namespaces mapped to the model that declared them.
      def workflow_namespaces_for(model)
        return [] if model.name.nil?
        return Array(model.try(:workflow_namespace)) unless model.respond_to?(:state_machine_definitions)

        model.state_machine_definitions.each_value.filter_map do |machine|
          namespace = machine.workflow_namespace_for(model).to_s
          namespace unless inherited_namespace?(model.superclass, machine, namespace)
        end
      end

      def inherited_namespace?(parent, machine, namespace)
        parent.respond_to?(:state_machine_definitions) &&
          parent.state_machine_definitions.value?(machine) &&
          machine.workflow_namespace_for(parent).to_s == namespace
      end

      def active_record_models
        @active_record_models ||= begin
          ::Rails.application&.eager_load!
          ::ActiveRecord::Base.descendants.reject(&:abstract_class?)
        end
      end
    end
  end
end
