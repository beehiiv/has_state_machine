# frozen_string_literal: true

require "stringio"
require "ruby_lsp/has_state_machine/rails_server_addon"

RSpec.describe RubyLsp::HasStateMachine::RailsServerAddon do
  let(:stdout) { StringIO.new }
  let(:addon) { described_class.new(stdout, StringIO.new, {}) }

  def last_result
    json = stdout.string.split("\r\n\r\n").last
    JSON.parse(json, symbolize_names: true)
  end

  describe "#execute" do
    it "resolves the model from symbol-keyed params (as sent by ruby-lsp-rails)" do
      addon.execute("model_for_workflow_namespace", {workflow_namespace: "Workflow::Post"})

      expect(last_result).to eq(result: {name: "Post"})
    end

    it "also accepts string-keyed params" do
      addon.execute("model_for_workflow_namespace", {"workflow_namespace" => "Workflow::Post"})

      expect(last_result).to eq(result: {name: "Post"})
    end

    it "returns a nil result for unknown namespaces" do
      addon.execute("model_for_workflow_namespace", {workflow_namespace: "Workflow::Missing"})

      expect(last_result).to eq(result: nil)
    end
  end
end
