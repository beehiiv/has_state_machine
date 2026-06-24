# frozen_string_literal: true

require "active_support/core_ext/string/inflections"
require "ruby_lsp/ruby_lsp_rails/server"
require_relative "workflow_resolver"

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
        model = conventional_model_for_workflow_namespace(workflow_namespace) ||
          loaded_model_for_workflow_namespace(workflow_namespace) ||
          models_by_workflow_namespace[workflow_namespace]
        return unless model

        {name: model.name}
      end

      def conventional_model_for_workflow_namespace(workflow_namespace)
        return unless workflow_namespace.to_s.start_with?(WorkflowResolver::WORKFLOW_PREFIX)

        model = workflow_namespace.to_s.delete_prefix(WorkflowResolver::WORKFLOW_PREFIX).safe_constantize
        model if model_matches_workflow_namespace?(model, workflow_namespace)
      end

      def loaded_model_for_workflow_namespace(workflow_namespace)
        active_record_models.find do |model|
          model_matches_workflow_namespace?(model, workflow_namespace)
        end
      end

      def models_by_workflow_namespace
        @models_by_workflow_namespace ||= eager_loaded_active_record_models.each_with_object({}) do |model, index|
          next unless model.respond_to?(:workflow_namespace)

          index[model.workflow_namespace] = model
        end
      end

      def active_record_models
        ::ActiveRecord::Base.descendants.reject(&:abstract_class?)
      end

      def eager_loaded_active_record_models
        @eager_loaded_active_record_models ||= begin
          ::Rails.application&.eager_load!
          active_record_models
        end
      end

      def model_matches_workflow_namespace?(model, workflow_namespace)
        model.is_a?(Class) &&
          model < ::ActiveRecord::Base &&
          !model.abstract_class? &&
          model.respond_to?(:workflow_namespace) &&
          model.workflow_namespace == workflow_namespace
      end
    end
  end
end
