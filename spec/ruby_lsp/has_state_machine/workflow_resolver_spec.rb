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

    it "returns nil for top-level class names without a namespace" do
      expect(described_class.workflow_namespace_for("Post")).to be_nil
      expect(described_class.workflow_namespace_for("::Post")).to be_nil
    end
  end

  describe ".class_name_from_nesting" do
    it "joins compact and nested module/class segments" do
      expect(described_class.class_name_from_nesting(["Workflow", "Post::Draft"])).to eq("Workflow::Post::Draft")
      expect(
        described_class.class_name_from_nesting(["Workflow::AdNetwork", "Advertisement::Active"])
      ).to eq("Workflow::AdNetwork::Advertisement::Active")
    end

    it "resets outer segments when an inner segment is top-level anchored with ::" do
      expect(
        described_class.class_name_from_nesting(["Outer", "::Workflow::Post::Draft"])
      ).to eq("Workflow::Post::Draft")
    end

    it "returns nil for empty nesting or singleton class scopes" do
      expect(described_class.class_name_from_nesting([])).to be_nil
      expect(described_class.class_name_from_nesting(["Workflow", "Post::Draft", "<Class:Draft>"])).to be_nil
    end
  end
end
