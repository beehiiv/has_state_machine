# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/internal"
require "ruby_lsp/has_state_machine/addon"

module RubyLspHasStateMachineDefinitionSpec
  FakeCall = Struct.new(:message, :receiver, :name)
  FakeNodeContext = Struct.new(:node, :call_node, :nesting)
  FakeEntry = Struct.new(:uri, :location, :name_location)
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
end

RSpec.describe RubyLsp::HasStateMachine::Definition do
  let(:fakes) { RubyLspHasStateMachineDefinitionSpec }
  let(:entry) { fakes::FakeEntry.new("file:///app/models/post.rb", fakes::FakeLocation.new(3, 3, 6, 10)) }
  let(:registry) { RubyLsp::HasStateMachine::NamespaceRegistry.new }

  describe "#on_call_node_enter" do
    it "pushes LocationLink for object calls" do
      object_node = fakes::FakeCall.new("object")
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]})
      )

      listener.on_call_node_enter(object_node)

      expect(response).to all(be_a(RubyLsp::Interface::LocationLink))
      expect(response.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
    end

    it "pushes model method locations for object method calls" do
      object_node = fakes::FakeCall.new("object")
      method_node = fakes::FakeCall.new("published?", object_node)
      method_entry = fakes::FakeEntry.new(
        "file:///app/models/post.rb",
        fakes::FakeLocation.new(7, 9, 2, 5),
        fakes::FakeLocation.new(7, 7, 6, 16)
      )
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

      expect(response.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(response.first.target_range.start.line).to eq(6)
      expect(response.first.target_selection_range.start.character).to eq(6)
    end

    it "resolves setter calls using the setter method name when defined" do
      object_node = fakes::FakeCall.new("object")
      setter_node = fakes::FakeCall.new("unsubscribe_source", object_node, :unsubscribe_source=)
      setter_entry = fakes::FakeEntry.new("file:///app/models/post.rb", fakes::FakeLocation.new(12, 12, 6, 25))
      response = []
      listener = build_listener(
        response: response,
        node: setter_node,
        call_node: setter_node,
        index: fakes::FakeIndex.new(
          entries: {"Post" => [entry]},
          methods: {["Post", "unsubscribe_source="] => [setter_entry]}
        )
      )

      listener.on_call_node_enter(setter_node)

      expect(response.first.target_range.start.line).to eq(11)
    end

    it "resolves custom workflow namespaces from the static namespace registry" do
      object_node = fakes::FakeCall.new("object")
      custom_entry = fakes::FakeEntry.new("file:///app/models/custom_post.rb", fakes::FakeLocation.new(1, 1, 6, 16))
      registry.register(
        uri: "file:///app/models/custom_post.rb",
        workflow_namespace: "Publishing::Post",
        model_name: "CustomPost"
      )
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        nesting: ["Publishing", "Post::Draft"],
        index: fakes::FakeIndex.new(entries: {"CustomPost" => [custom_entry]})
      )

      listener.on_call_node_enter(object_node)

      expect(response.map(&:target_uri)).to eq(["file:///app/models/custom_post.rb"])
    end

    it "prefers a registered workflow namespace over the naming convention" do
      object_node = fakes::FakeCall.new("object")
      custom_entry = fakes::FakeEntry.new("file:///app/models/custom_post.rb", fakes::FakeLocation.new(1, 1, 6, 16))
      registry.register(
        uri: "file:///app/models/custom_post.rb",
        workflow_namespace: "Workflow::Post",
        model_name: "CustomPost"
      )
      response = []
      listener = build_listener(
        response: response,
        node: object_node,
        call_node: object_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry], "CustomPost" => [custom_entry]})
      )

      listener.on_call_node_enter(object_node)

      expect(response.map(&:target_uri)).to eq(["file:///app/models/custom_post.rb"])
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

      expect(response.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
    end

    it "resolves methods chained through reload and lock!" do
      %w[reload lock!].each do |chain_method|
        object_node = fakes::FakeCall.new("object")
        chained_node = fakes::FakeCall.new(chain_method, object_node)
        method_node = fakes::FakeCall.new("published?", chained_node)
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

        expect(response.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
        expect(response.first.target_range.start.line).to eq(6)
      end
    end

    it "ignores methods chained through non-self-returning calls" do
      object_node = fakes::FakeCall.new("object")
      parent_node = fakes::FakeCall.new("parent", object_node)
      method_node = fakes::FakeCall.new("published?", parent_node)
      response = []
      listener = build_listener(
        response: response,
        node: method_node,
        call_node: method_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]})
      )

      listener.on_call_node_enter(method_node)

      expect(response).to be_empty
    end

    it "ignores unrelated call nodes" do
      unrelated_node = fakes::FakeCall.new("some_helper")
      response = []
      listener = build_listener(
        response: response,
        node: unrelated_node,
        call_node: unrelated_node,
        index: fakes::FakeIndex.new(entries: {"Post" => [entry]})
      )

      listener.on_call_node_enter(unrelated_node)

      expect(response).to be_empty
    end
  end

  describe "end-to-end RubyLsp::Requests::Definition integration" do
    let(:global_state) do
      state = RubyLsp::GlobalState.new
      state.instance_variable_set(:@has_type_checker, false)
      state
    end
    let(:addon) { RubyLsp::HasStateMachine::Addon.new }

    around do |example|
      original_addons = RubyLsp::Addon.addons.dup
      RubyLsp::HasStateMachine::NamespaceRegistry.clear
      addon.activate(global_state, Queue.new)
      RubyLsp::Addon.addons = [addon]
      example.run
    ensure
      addon.deactivate
      RubyLsp::Addon.addons = original_addons
      RubyLsp::HasStateMachine::NamespaceRegistry.clear
    end

    def index_file(path, source)
      uri = URI::Generic.from_path(path: path)
      global_state.index.index_single(uri, source)
      uri
    end

    def complete_indexing!
      global_state.index.instance_variable_set(:@initial_indexing_completed, true)
    end

    def definition_for(path, source, line:, character:)
      uri = URI::Generic.from_path(path: path)
      document = RubyLsp::RubyDocument.new(source: source, version: 1, uri: uri, global_state: global_state)
      dispatcher = Prism::Dispatcher.new

      RubyLsp::Requests::Definition.new(
        document,
        global_state,
        {line: line, character: character},
        dispatcher,
        RubyLsp::SorbetLevel.ignore
      ).perform
    end

    before do
      index_file("/gems/has_state_machine/lib/has_state_machine/state.rb", <<~RUBY)
        module HasStateMachine
          class State < String
            attr_reader :object
          end
        end
      RUBY

      index_file("/app/services/workflow/state.rb", <<~RUBY)
        module Workflow
          class State < HasStateMachine::State
          end
        end
      RUBY

      index_file("/app/models/post.rb", <<~RUBY)
        class Post < ApplicationRecord
          has_state_machine states: %i[draft published archived]

          def custom_helper
            true
          end

          def title=(value)
            @title = value
          end
        end
      RUBY

      index_file("/app/models/other_model.rb", <<~RUBY)
        class OtherModel
          def custom_helper
            false
          end

          def published?
            false
          end

          def completed_at
            nil
          end
        end
      RUBY

      index_file("/app/models/subscription.rb", <<~RUBY)
        class Subscription < ApplicationRecord
          has_state_machine states: %i[unset active inactive],
            state_attribute: :marketing_status,
            workflow_namespace: "Workflow::SubscriptionMarketing",
            prefix: :marketing
        end
      RUBY

      index_file("/app/models/domain_configurations/email.rb", <<~RUBY)
        module DomainConfigurations
          class Email < ApplicationRecord
            def verify_dns!
              true
            end
          end
        end
      RUBY
    end

    it "returns only LocationLink entries targeting the model on object calls (clearing State#object)" do
      source = <<~RUBY
        module Workflow
          class Post::Draft < Workflow::State
            after_transition do
              object.custom_helper
            end
          end
        end
      RUBY
      path = "/app/services/workflow/post/draft.rb"
      index_file(path, source)
      complete_indexing!

      results = definition_for(path, source, line: 3, character: 8)

      expect(results).to all(be_a(RubyLsp::Interface::LocationLink))
      expect(results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
    end

    it "resolves model methods, indexed state predicates, and columns without unrelated guesses" do
      source = <<~RUBY
        module Workflow
          class Post::Draft < Workflow::State
            def run
              object.custom_helper
              object.published?
              object.completed_at
              self.object.reload&.custom_helper
            end
          end
        end
      RUBY
      path = "/app/services/workflow/post/draft.rb"
      index_file(path, source)
      complete_indexing!

      custom_results = definition_for(path, source, line: 3, character: 15)
      predicate_results = definition_for(path, source, line: 4, character: 15)
      column_results = definition_for(path, source, line: 5, character: 15)
      chained_results = definition_for(path, source, line: 6, character: 28)

      [custom_results, predicate_results, column_results, chained_results].each do |results|
        expect(results).to all(be_a(RubyLsp::Interface::LocationLink))
        expect(results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      end
      expect(custom_results.first.target_selection_range.start.line).to eq(3)
      expect(predicate_results.first.target_selection_range.start.line).to eq(1)
      expect(column_results.first.target_selection_range.start.line).to eq(0)
      expect(chained_results.first.target_selection_range.start.line).to eq(3)
    end

    it "resolves custom workflow_namespace models and prefixed predicates statically" do
      source = <<~RUBY
        module Workflow
          class SubscriptionMarketing::Active < Workflow::State
            after_transition do
              object.marketing_active?
            end
          end
        end
      RUBY
      path = "/app/services/workflow/subscription_marketing/active.rb"
      index_file(path, source)
      complete_indexing!

      object_results = definition_for(path, source, line: 3, character: 8)
      predicate_results = definition_for(path, source, line: 3, character: 16)

      expect(object_results.map(&:target_uri)).to eq(["file:///app/models/subscription.rb"])
      expect(predicate_results.map(&:target_uri)).to eq(["file:///app/models/subscription.rb"])
    end

    it "does not resolve abstract workflow base classes whose namespace maps to a module" do
      source = <<~RUBY
        module Workflow
          module DomainConfigurations
            class Base < Workflow::State
              def log
                object.verify_dns!
              end
            end
          end
        end
      RUBY
      path = "/app/services/workflow/domain_configurations/base.rb"
      index_file(path, source)
      complete_indexing!

      results = definition_for(path, source, line: 4, character: 10)

      expect(results.map(&:target_uri)).not_to include("file:///app/models/domain_configurations/email.rb")
    end

    it "ignores non-workflow classes that call object" do
      source = <<~RUBY
        module Workflow
          class FakePost::Serializer
            def render
              object.custom_helper
            end
          end
        end
      RUBY
      path = "/app/serializers/workflow/fake_post/serializer.rb"
      index_file("/app/models/fake_post.rb", "class FakePost; def custom_helper; end; end")
      index_file(path, source)
      complete_indexing!

      results = definition_for(path, source, line: 3, character: 8)

      expect(results.map(&:target_uri)).not_to include("file:///app/models/fake_post.rb")
    end

    it "resolves workflow objects inside validate lambdas, setters, and unsaved files, but skips class methods" do
      complete_indexing!

      unsaved_source = <<~RUBY
        module Workflow
          class Post::UnsavedState < Workflow::State
            validate :check, if: -> { object.published? }

            def apply
              object.title = "Updated"
            end

            def self.build
              object
            end
          end
        end
      RUBY
      path = "/app/services/workflow/post/unsaved_state.rb"

      lambda_results = definition_for(path, unsaved_source, line: 2, character: 39)
      setter_results = definition_for(path, unsaved_source, line: 5, character: 14)
      singleton_results = definition_for(path, unsaved_source, line: 9, character: 8)

      expect(lambda_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(setter_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(setter_results.first.target_selection_range.start.line).to eq(7)
      expect(singleton_results.map(&:target_uri)).not_to include("file:///app/models/post.rb")
    end

    it "resolves workflow objects before initial indexing finishes" do
      source = <<~RUBY
        module Workflow
          class Post::Draft < Workflow::State
            def run
              object
            end
          end
        end
      RUBY
      path = "/app/services/workflow/post/draft.rb"
      index_file(path, source)

      results = definition_for(path, source, line: 3, character: 8)

      expect(results).to all(be_a(RubyLsp::Interface::LocationLink))
      expect(results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
    end

    it "resolves workflow objects when the superclass uses an aliased namespace" do
      index_file("/app/services/shared_alias.rb", "SharedAlias = ::Workflow")

      source = <<~RUBY
        module Workflow
          class Post::Draft < SharedAlias::State
            def run
              object.custom_helper
            end
          end
        end
      RUBY
      path = "/app/services/workflow/post/draft.rb"
      index_file(path, source)
      complete_indexing!

      object_results = definition_for(path, source, line: 3, character: 8)
      method_results = definition_for(path, source, line: 3, character: 15)

      expect(object_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(method_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(method_results.first.target_selection_range.start.line).to eq(3)
    end

    it "resolves superclass names in the lexical scope of compact class declarations" do
      index_file("/app/services/state.rb", "class State < HasStateMachine::State; end")
      index_file("/app/services/workflow/post/state.rb", <<~RUBY)
        module Workflow
          module Post
            class State
            end
          end
        end
      RUBY

      source = <<~RUBY
        class Workflow::Post::Draft < State
          def run
            object.custom_helper
          end
        end
      RUBY
      path = "/app/services/workflow/post/draft.rb"
      index_file(path, source)
      complete_indexing!

      object_results = definition_for(path, source, line: 2, character: 6)
      method_results = definition_for(path, source, line: 2, character: 13)

      expect(object_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(method_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(method_results.first.target_selection_range.start.line).to eq(3)
    end

    it "keeps resolving object even when String has a non-module constant mixin that breaks linearized_ancestors_of" do
      index_file("/gems/bad_gem/lib/string_ext.rb", <<~RUBY)
        StringVersion = "1.0"

        class String
          include StringVersion
        end
      RUBY

      source = <<~RUBY
        module Workflow
          class Post::Draft < Workflow::State
            after_transition do
              object.custom_helper
              object.published?
            end
          end
        end
      RUBY
      path = "/app/services/workflow/post/draft.rb"
      index_file(path, source)
      complete_indexing!

      first_results = definition_for(path, source, line: 3, character: 8)
      second_results = definition_for(path, source, line: 4, character: 8)

      expect(first_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(second_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
    end

    it "resolves object inside model-scoped workflow concern modules" do
      source = <<~RUBY
        module Workflow
          module Post
            module PublishChecks
              def ready?
                object.custom_helper
              end
            end
          end
        end
      RUBY
      path = "/app/services/workflow/post/publish_checks.rb"
      index_file(path, source)
      complete_indexing!

      object_results = definition_for(path, source, line: 4, character: 10)
      method_results = definition_for(path, source, line: 4, character: 17)

      expect(object_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(method_results.map(&:target_uri)).to eq(["file:///app/models/post.rb"])
      expect(method_results.first.target_selection_range.start.line).to eq(3)
    end
  end

  def build_listener(response:, node:, call_node:, index:, nesting: ["Workflow", "Post::Draft"])
    dispatcher = RubyLspHasStateMachineDefinitionSpec::FakeDispatcher.new
    node_context = RubyLspHasStateMachineDefinitionSpec::FakeNodeContext.new(node, call_node, nesting)

    described_class.new(
      response,
      nil,
      node_context,
      dispatcher,
      index: index,
      namespace_registry: registry
    )
  end
end
