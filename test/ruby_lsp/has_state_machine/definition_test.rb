# frozen_string_literal: true

require "test_helper"
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

class RubyLsp::HasStateMachine::DefinitionTest < ActiveSupport::TestCase
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

    def initialize(delegate_responses = {}, association_responses = {})
      @delegate_responses = delegate_responses
      @association_responses = association_responses
      @requests = []
      @association_requests = []
    end

    def delegate_request(**params)
      @requests << params
      @delegate_responses[[params.fetch(:request_name), params[:model_name], params[:association_name], params[:workflow_namespace]]]
    end

    def association_target(model_name:, association_name:)
      @association_requests << [model_name, association_name]
      @association_responses[[model_name, association_name]]
    end
  end

  def setup
    @entry = FakeEntry.new("file:///app/models/post.rb", FakeLocation.new(3, 3, 6, 10))
  end

  describe "#on_call_node_enter" do
    it "pushes the model location for object calls" do
      object_node = FakeCall.new("object")
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        index: FakeIndex.new(entries: {"Post" => [@entry]})
      )

      listener.on_call_node_enter(object_node)

      assert_equal ["file:///app/models/post.rb"], response.map(&:uri)
    end

    it "pushes model method locations for object method calls" do
      object_node = FakeCall.new("object")
      method_node = FakeCall.new("published?", object_node)
      method_entry = FakeEntry.new("file:///app/models/post.rb", FakeLocation.new(7, 7, 6, 16))
      response = []
      listener = build_listener(
        response: response,
        node: method_node,
        call_node: method_node,
        index: FakeIndex.new(
          entries: {"Post" => [@entry]},
          methods: {["Post", "published?"] => [method_entry]}
        )
      )

      listener.on_call_node_enter(method_node)

      assert_equal ["file:///app/models/post.rb"], response.map(&:uri)
      assert_equal 6, response.first.range.start.line
    end

    it "uses Rails associations when the index does not resolve the method" do
      object_node = FakeCall.new("object")
      method_node = FakeCall.new("author", object_node)
      author_entry = FakeEntry.new("file:///app/models/author.rb", FakeLocation.new(1, 1, 6, 12))
      rails_client = FakeRailsClient.new({}, ["Post", "author"] => {name: "Author"})
      response = []
      listener = build_listener(
        response: response,
        node: method_node,
        call_node: method_node,
        index: FakeIndex.new(entries: {"Post" => [@entry], "Author" => [author_entry]}),
        rails_client: rails_client
      )

      listener.on_call_node_enter(method_node)

      assert_equal ["file:///app/models/author.rb"], response.map(&:uri)
    end

    it "asks Rails for custom workflow namespaces" do
      object_node = FakeCall.new("object")
      custom_entry = FakeEntry.new("file:///app/models/custom_post.rb", FakeLocation.new(1, 1, 6, 16))
      rails_client = FakeRailsClient.new(
        ["model_for_workflow_namespace", nil, nil, "Publishing::Post"] => {name: "CustomPost"}
      )
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        nesting: ["Publishing", "Post::Draft"],
        index: FakeIndex.new(entries: {"CustomPost" => [custom_entry]}),
        rails_client: rails_client
      )

      listener.on_call_node_enter(object_node)

      assert_equal ["file:///app/models/custom_post.rb"], response.map(&:uri)
    end
  end

  private

  def build_listener(response:, node:, call_node:, index:, rails_client: nil, nesting: ["Workflow", "Post::Draft"])
    dispatcher = FakeDispatcher.new
    node_context = FakeNodeContext.new(node, call_node, nesting)

    RubyLsp::HasStateMachine::Definition.new(
      response,
      nil,
      node_context,
      dispatcher,
      index: index,
      rails_client: rails_client
    )
  end
end
