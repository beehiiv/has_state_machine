# frozen_string_literal: true

require "ruby_lsp/ruby_lsp_rails/server"

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
            send_result(model_for_workflow_namespace(params.fetch("workflow_namespace")))
          else
            raise NotImplementedError, "Unknown request: #{request}"
          end
        end
      end

      private

      def model_for_workflow_namespace(workflow_namespace)
        model = models_by_workflow_namespace[workflow_namespace]
        return unless model

        {name: model.name}
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
