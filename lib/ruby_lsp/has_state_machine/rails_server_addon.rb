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

      ##
      # Fast path: for the default "Workflow::<Model>" namespace, autoload just
      # that one constant instead of eager loading the whole application. Only
      # custom workflow_namespace configurations need the full scan below.
      def conventional_model_for(workflow_namespace)
        workflow_namespace = workflow_namespace.to_s
        return unless workflow_namespace.start_with?("Workflow::")

        model = workflow_namespace.delete_prefix("Workflow::").safe_constantize
        model if model.try(:workflow_namespace) == workflow_namespace
      end

      def models_by_workflow_namespace
        @models_by_workflow_namespace ||= active_record_models.each_with_object({}) do |model, index|
          next unless model.respond_to?(:workflow_namespace)

          index[model.workflow_namespace] = model
        end
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
