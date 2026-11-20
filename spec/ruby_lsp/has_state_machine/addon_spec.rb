# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/internal"
require "ruby_lsp/has_state_machine/addon"

RSpec.describe RubyLsp::HasStateMachine::Addon do
  let(:addon) { described_class.new }
  let(:queue) { Queue.new }
  let(:registry) { RubyLsp::HasStateMachine::NamespaceRegistry.instance }

  before { registry.clear }
  after { registry.clear }

  def drain(queue)
    messages = []
    messages << queue.pop until queue.empty?
    messages
  end

  describe "#activate" do
    it "activates immediately without contacting Ruby LSP Rails and logs activation" do
      allow(::RubyLsp::Addon).to receive(:get).and_raise("should not touch Ruby LSP Rails")

      addon.activate(nil, queue)

      log = drain(queue).map { |message| message.params.message }.join("\n")
      expect(log).to include("Activating Has State Machine Ruby LSP add-on v#{HasStateMachine::VERSION}")
    end
  end

  describe "#workspace_did_change_watched_files" do
    it "evicts namespaces for deleted files and keeps namespaces for changed files" do
      registry.register(
        uri: "file:///app/models/deleted_model.rb",
        workflow_namespace: "Workflow::Deleted",
        model_name: "DeletedModel"
      )
      registry.register(
        uri: "file:///app/models/changed_model.rb",
        workflow_namespace: "Workflow::Changed",
        model_name: "ChangedModel"
      )

      addon.workspace_did_change_watched_files([
        {uri: "file:///app/models/deleted_model.rb", type: RubyLsp::Constant::FileChangeType::DELETED},
        {uri: "file:///app/models/changed_model.rb", type: RubyLsp::Constant::FileChangeType::CHANGED}
      ])

      expect(registry.model_for("Workflow::Deleted")).to be_nil
      expect(registry.model_for("Workflow::Changed")).to eq("ChangedModel")
    end
  end

  describe "#deactivate" do
    it "clears the namespace registry" do
      registry.register(
        uri: "file:///app/models/subscription.rb",
        workflow_namespace: "Workflow::SubscriptionMarketing",
        model_name: "Subscription"
      )

      addon.deactivate

      expect(registry.model_for("Workflow::SubscriptionMarketing")).to be_nil
    end
  end
end
