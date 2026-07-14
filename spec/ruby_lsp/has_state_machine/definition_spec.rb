# frozen_string_literal: true

require "ruby_lsp/has_state_machine/definition"

module RubyLsp
  module Interface
    unless const_defined?(:Position, false)
      class Position
        attr_reader :line, :character

        def initialize(line:, character:)
          @line = line
          @character = character
        end
      end
    end

    unless const_defined?(:Range, false)
      class Range
        attr_reader :start, :end

        def initialize(**kwargs)
          @start = kwargs.fetch(:start)
          @end = kwargs.fetch(:end)
        end
      end
    end

    unless const_defined?(:Location, false)
      class Location
        attr_reader :uri, :range

        def initialize(uri:, range:)
          @uri = uri
          @range = range
        end
      end
    end
  end
end

module RubyLspHasStateMachineDefinitionSpec
  FakeCall = Struct.new(:message, :receiver)
  FakeNodeContext = Struct.new(:node, :call_node, :nesting)
  FakeEntry = Struct.new(:uri, :location)
  FakeLocation = Struct.new(:start_line, :end_line, :start_column, :end_column)

  class FakeDispatcher
    attr_reader :events

    def register(_listener, *events)
      @events = events
    end
  end

  class FakeIndex
    def initialize(entries: {}, methods: {})
      @entries = entries
      @methods = methods
    end

    def [](name)
      @entries[name]
    end

    def resolve_method(method_name, owner_name)
      @methods[[owner_name, method_name]]
    end
  end

  class FakeRailsClient
    attr_reader :requests, :association_requests

    attr_writer :connected

    def initialize(delegate_responses = {}, association_responses = {})
      @delegate_responses = delegate_responses
      @association_responses = association_responses
      @connected = true
      @requests = []
      @association_requests = []
    end

    def connected?
      @connected
    end

    def delegate_request(**params)
      @requests << params
      key = [
        params.fetch(:request_name),
        params[:model_name],
        params[:association_name],
        params[:workflow_namespace]
      ]
      @delegate_responses[key]
    end

    def association_target(model_name:, association_name:)
      @association_requests << [model_name, association_name]
      @association_responses[[model_name, association_name]]
    end
  end
end

RSpec.describe RubyLsp::HasStateMachine::Definition do
  let(:fakes) { RubyLspHasStateMachineDefinitionSpec }
  let(:entry) { fakes::FakeEntry.new("file:///app/models/post.rb", fakes::FakeLocation.new(3, 3, 6, 10)) }

  describe "#on_call_node_enter" do
    it "pushes the model location for object calls" do
      object_node = fakes::FakeCall.new("object")
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]})
      )

      listener.on_call_node_enter(object_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/post.rb"])
    end

    it "pushes model method locations for object method calls" do
      object_node = fakes::FakeCall.new("object")
      method_node = fakes::FakeCall.new("published?", object_node)
      method_entry = fakes::FakeEntry.new("file:///app/models/post.rb", fakes::FakeLocation.new(7, 7, 6, 16))
      response = []
      listener = build_listener(
        response: response,
        node: method_node,
        call_node: method_node,
        index: fakes::FakeIndex.new(
          entries: {"Post" => [entry]},
          methods: {["Post", "published?"] => [method_entry]}
        )
      )

      listener.on_call_node_enter(method_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/post.rb"])
      expect(response.first.range.start.line).to eq(6)
    end

    it "uses Rails associations when the index does not resolve the method" do
      object_node = fakes::FakeCall.new("object")
      method_node = fakes::FakeCall.new("author", object_node)
      author_entry = fakes::FakeEntry.new("file:///app/models/author.rb", fakes::FakeLocation.new(1, 1, 6, 12))
      rails_client = fakes::FakeRailsClient.new({}, ["Post", "author"] => {name: "Author"})
      response = []
      listener = build_listener(
        response: response,
        node: method_node,
        call_node: method_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry], "Author" => [author_entry]}),
        rails_client: rails_client
      )

      listener.on_call_node_enter(method_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/author.rb"])
    end

    it "asks Rails for custom workflow namespaces" do
      object_node = fakes::FakeCall.new("object")
      custom_entry = fakes::FakeEntry.new("file:///app/models/custom_post.rb", fakes::FakeLocation.new(1, 1, 6, 16))
      rails_client = fakes::FakeRailsClient.new(
        ["model_for_workflow_namespace", nil, nil, "Publishing::Post"] => {name: "CustomPost"}
      )
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        nesting: ["Publishing", "Post::Draft"],
        index: fakes::FakeIndex.new(entries: {"CustomPost" => [custom_entry]}),
        rails_client: rails_client
      )

      listener.on_call_node_enter(object_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/custom_post.rb"])
    end

    it "falls back to the model class for column attribute methods with no definition" do
      object_node = fakes::FakeCall.new("object")
      method_node = fakes::FakeCall.new("completed_at", object_node)
      response = []
      listener = build_listener(
        response: response,
        node: method_node,
        call_node: method_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]})
      )

      listener.on_call_node_enter(method_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/post.rb"])
    end

    it "resolves methods chained through reload" do
      object_node = fakes::FakeCall.new("object")
      reload_node = fakes::FakeCall.new("reload", object_node)
      method_node = fakes::FakeCall.new("published?", reload_node)
      method_entry = fakes::FakeEntry.new("file:///app/models/post.rb", fakes::FakeLocation.new(7, 7, 6, 16))
      response = []
      listener = build_listener(
        response: response,
        node: method_node,
        call_node: method_node,
        index: fakes::FakeIndex.new(
          entries: {"Post" => [entry]},
          methods: {["Post", "published?"] => [method_entry]}
        )
      )

      listener.on_call_node_enter(method_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/post.rb"])
      expect(response.first.range.start.line).to eq(6)
    end

    it "ignores methods chained through non-self-returning calls" do
      object_node = fakes::FakeCall.new("object")
      parent_node = fakes::FakeCall.new("parent", object_node)
      method_node = fakes::FakeCall.new("published?", parent_node)
      rails_client = fakes::FakeRailsClient.new
      listener = build_listener(
        response: [],
        node: method_node,
        call_node: method_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]}),
        rails_client: rails_client
      )

      listener.on_call_node_enter(method_node)

      expect(rails_client.requests).to be_empty
    end

    it "falls back to the naming convention when the Rails client is disconnected" do
      object_node = fakes::FakeCall.new("object")
      rails_client = fakes::FakeRailsClient.new
      rails_client.connected = false
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]}),
        rails_client: rails_client
      )

      listener.on_call_node_enter(object_node)

      expect(rails_client.requests).to be_empty
      expect(response.map(&:uri)).to eq(["file:///app/models/post.rb"])
    end

    it "resolves via convention when there is no Rails client" do
      object_node = fakes::FakeCall.new("object")
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]}),
        rails_client: nil
      )

      listener.on_call_node_enter(object_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/post.rb"])
    end

    it "does not contact Rails for unrelated call nodes" do
      unrelated_node = fakes::FakeCall.new("some_helper")
      rails_client = fakes::FakeRailsClient.new
      listener = build_listener(
        response: [],
        node: unrelated_node,
        call_node: unrelated_node,
        index: fakes::FakeIndex.new,
        rails_client: rails_client
      )

      listener.on_call_node_enter(unrelated_node)

      expect(rails_client.requests).to be_empty
    end

    it "shares the model name cache across listeners" do
      object_node = fakes::FakeCall.new("object")
      rails_client = fakes::FakeRailsClient.new(
        ["model_for_workflow_namespace", nil, nil, "Workflow::Post"] => {name: "Post"}
      )
      cache = {}
      index = fakes::FakeIndex.new(entries: {"Post" => [entry]})

      2.times do
        listener = build_listener(
          response: [],
          node: object_node,
          call_node: object_node,
          index: index,
          rails_client: rails_client,
          model_name_cache: cache
        )
        listener.on_call_node_enter(object_node)
      end

      expect(rails_client.requests.length).to eq(1)
      expect(cache).to eq("Workflow::Post" => "Post")
    end

    it "prefers the model configured workflow namespace over the convention" do
      object_node = fakes::FakeCall.new("object")
      custom_entry = fakes::FakeEntry.new("file:///app/models/custom_post.rb", fakes::FakeLocation.new(1, 1, 6, 16))
      rails_client = fakes::FakeRailsClient.new(
        ["model_for_workflow_namespace", nil, nil, "Workflow::Post"] => {name: "CustomPost"}
      )
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry], "CustomPost" => [custom_entry]}),
        rails_client: rails_client
      )

      listener.on_call_node_enter(object_node)

      expect(response.map(&:uri)).to eq(["file:///app/models/custom_post.rb"])
    end
  end

  def build_listener(response:, node:, call_node:, index:, rails_client: nil, model_name_cache: nil,
    nesting: ["Workflow", "Post::Draft"])
    dispatcher = RubyLspHasStateMachineDefinitionSpec::FakeDispatcher.new
    node_context = RubyLspHasStateMachineDefinitionSpec::FakeNodeContext.new(node, call_node, nesting)

    described_class.new(
      response,
      nil,
      node_context,
      dispatcher,
      index: index,
      rails_client: rails_client,
      model_name_cache: model_name_cache
    )
  end
end
