# frozen_string_literal: true

require "ruby_lsp/has_state_machine/namespace_registry"

RSpec.describe RubyLsp::HasStateMachine::NamespaceRegistry do
  subject(:registry) { described_class.new }

  describe "#register and #model_for" do
    it "registers and resolves custom workflow namespaces" do
      registry.register(
        uri: "file:///app/models/subscription.rb",
        workflow_namespace: "Workflow::SubscriptionMarketing",
        model_name: "Subscription"
      )

      expect(registry.model_for("Workflow::SubscriptionMarketing")).to eq("Subscription")
      expect(registry.model_for("::Workflow::SubscriptionMarketing")).to eq("Subscription")
    end

    it "normalizes leading :: on namespace and model name" do
      registry.register(
        uri: "file:///app/models/dkim_backfill.rb",
        workflow_namespace: "::Workflow::DkimBackfill",
        model_name: "::BeehiivMta::DkimBackfill"
      )

      expect(registry.model_for("Workflow::DkimBackfill")).to eq("BeehiivMta::DkimBackfill")
    end

    it "ignores blank namespaces or model names" do
      registry.register(uri: "file:///a.rb", workflow_namespace: "", model_name: "Post")
      registry.register(uri: "file:///a.rb", workflow_namespace: "Workflow::Post", model_name: "")

      expect(registry.model_for("Workflow::Post")).to be_nil
    end
  end

  describe "#clear_uri" do
    it "removes only the namespaces registered for that URI" do
      registry.register(
        uri: "file:///app/models/subscription.rb",
        workflow_namespace: "Workflow::SubscriptionMarketing",
        model_name: "Subscription"
      )
      registry.register(
        uri: "file:///app/models/subscription.rb",
        workflow_namespace: "Workflow::SubscriptionBilling",
        model_name: "Subscription"
      )
      registry.register(
        uri: "file:///app/models/dkim_backfill.rb",
        workflow_namespace: "Workflow::DkimBackfill",
        model_name: "BeehiivMta::DkimBackfill"
      )

      registry.clear_uri("file:///app/models/subscription.rb")

      expect(registry.model_for("Workflow::SubscriptionMarketing")).to be_nil
      expect(registry.model_for("Workflow::SubscriptionBilling")).to be_nil
      expect(registry.model_for("Workflow::DkimBackfill")).to eq("BeehiivMta::DkimBackfill")
    end

    it "preserves a namespace still declared by another URI" do
      registry.register(
        uri: "file:///app/models/post.rb",
        workflow_namespace: "Workflow::CustomPost",
        model_name: "Post"
      )
      registry.register(
        uri: "file:///app/models/post_extra.rb",
        workflow_namespace: "Workflow::CustomPost",
        model_name: "Post"
      )

      registry.clear_uri("file:///app/models/post.rb")

      expect(registry.model_for("Workflow::CustomPost")).to eq("Post")
    end
  end

  describe "#clear" do
    it "removes all registered namespaces" do
      registry.register(
        uri: "file:///app/models/subscription.rb",
        workflow_namespace: "Workflow::SubscriptionMarketing",
        model_name: "Subscription"
      )

      registry.clear

      expect(registry.model_for("Workflow::SubscriptionMarketing")).to be_nil
    end
  end
end
