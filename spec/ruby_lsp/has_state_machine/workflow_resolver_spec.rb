# frozen_string_literal: true

require "ruby_lsp/has_state_machine/workflow_resolver"

RSpec.describe RubyLsp::HasStateMachine::WorkflowResolver do
  describe ".model_name_for" do
    it "resolves a simple workflow class by convention" do
      expect(described_class.model_name_for("Workflow::Post::Draft")).to eq("Post")
    end

    it "resolves a nested workflow class by convention" do
      expect(
        described_class.model_name_for("Workflow::DomainConfigurations::Email::MtaPending")
      ).to eq("DomainConfigurations::Email")
    end

    it "ignores non-workflow class names" do
      expect(described_class.model_name_for("Admin::Post::Draft")).to be_nil
    end
  end

  describe ".workflow_namespace_for" do
    it "drops the final state class" do
      expect(
        described_class.workflow_namespace_for("Workflow::DomainConfigurations::Email::MtaPending")
      ).to eq("Workflow::DomainConfigurations::Email")
    end
  end
end
