# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/internal"
require "ruby_lsp/has_state_machine/addon"

module RubyLspHasStateMachineAddonSpec
  class FakeRunnerClient
    attr_reader :registrations

    def initialize(connected:)
      @connected = connected
      @registrations = []
    end

    def connected?
      @connected
    end

    def register_server_addon(path)
      @registrations << path
    end
  end

  FakeRailsAddon = Struct.new(:rails_runner_client)
end

RSpec.describe RubyLsp::HasStateMachine::Addon do
  let(:fakes) { RubyLspHasStateMachineAddonSpec }
  let(:addon) { described_class.new }
  let(:queue) { Queue.new }

  def drain(queue)
    messages = []
    messages << queue.pop until queue.empty?
    messages
  end

  def stub_rails_addon(client)
    allow(::RubyLsp::Addon).to receive(:get).and_return(fakes::FakeRailsAddon.new(client))
  end

  describe "#activate" do
    it "registers the server addon on a connected Rails runner client and logs activation" do
      client = fakes::FakeRunnerClient.new(connected: true)
      stub_rails_addon(client)

      addon.activate(nil, queue)

      expect(client.registrations).to contain_exactly(a_string_ending_with("rails_server_addon.rb"))
      log = drain(queue).map { |message| message.params.message }.join("\n")
      expect(log).to include("Activating Has State Machine Ruby LSP add-on v#{HasStateMachine::VERSION}")
      expect(log).to include("registered")
    end

    it "skips registration when the Rails runner client is not connected" do
      client = fakes::FakeRunnerClient.new(connected: false)
      stub_rails_addon(client)

      addon.activate(nil, queue)

      expect(client.registrations).to be_empty
      log = drain(queue).map { |message| message.params.message }.join("\n")
      expect(log).to include("unavailable")
    end

    it "activates without the Rails addon installed" do
      allow(::RubyLsp::Addon).to receive(:get).and_raise(::RubyLsp::Addon::AddonNotFoundError)

      addon.activate(nil, queue)

      log = drain(queue).map { |message| message.params.message }.join("\n")
      expect(log).to include("Activating Has State Machine Ruby LSP add-on")
    end
  end
end
