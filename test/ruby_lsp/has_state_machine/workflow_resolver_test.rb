# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/has_state_machine/workflow_resolver"

class RubyLsp::HasStateMachine::WorkflowResolverTest < ActiveSupport::TestCase
  describe ".model_name_for" do
    it "resolves a simple workflow class by convention" do
      assert_equal "Post", RubyLsp::HasStateMachine::WorkflowResolver.model_name_for("Workflow::Post::Draft")
    end

    it "resolves a nested workflow class by convention" do
      assert_equal(
        "DomainConfigurations::Email",
        RubyLsp::HasStateMachine::WorkflowResolver.model_name_for("Workflow::DomainConfigurations::Email::MtaPending")
      )
    end

    it "ignores non-workflow class names" do
      assert_nil RubyLsp::HasStateMachine::WorkflowResolver.model_name_for("Admin::Post::Draft")
    end
  end

  describe ".workflow_namespace_for" do
    it "drops the final state class" do
      assert_equal(
        "Workflow::DomainConfigurations::Email",
        RubyLsp::HasStateMachine::WorkflowResolver.workflow_namespace_for("Workflow::DomainConfigurations::Email::MtaPending")
      )
    end
  end
end
