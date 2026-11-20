# frozen_string_literal: true

require "ruby-lsp"
require "ruby_lsp/internal"
require "ruby_lsp/has_state_machine/indexing_enhancement"

RSpec.describe RubyLsp::HasStateMachine::IndexingEnhancement do
  let(:index) { RubyIndexer::Index.new }
  let(:registry) { RubyLsp::HasStateMachine::NamespaceRegistry.instance }

  before { registry.clear }
  after { registry.clear }

  def index_source(path, source)
    uri = URI::Generic.from_path(path: path)
    index.index_single(uri, source)
    uri
  end

  it "indexes the default state attribute reader and literal state predicates" do
    index_source("/app/models/post.rb", <<~RUBY)
      class Post < ApplicationRecord
        has_state_machine states: %i[draft published archived]
      end
    RUBY

    expect(index.resolve_method("status", "Post")).not_to be_nil
    expect(index.resolve_method("draft?", "Post")).not_to be_nil
    expect(index.resolve_method("published?", "Post")).not_to be_nil
    expect(index.resolve_method("archived?", "Post")).not_to be_nil
  end

  it "indexes frozen array literals, string arrays, and explicit arrays" do
    index_source("/app/models/boost_invite.rb", <<~RUBY)
      class BoostInvite < ApplicationRecord
        has_state_machine states: %i[pending accepted].freeze
        has_state_machine states: %w[open closed], state_attribute: :billing_state, prefix: :billing
        has_state_machine states: [:ready, "done"], attribute: :sync_state, suffix: true
      end
    RUBY

    expect(index.resolve_method("pending?", "BoostInvite")).not_to be_nil
    expect(index.resolve_method("accepted?", "BoostInvite")).not_to be_nil
    expect(index.resolve_method("billing_state", "BoostInvite")).not_to be_nil
    expect(index.resolve_method("billing_open?", "BoostInvite")).not_to be_nil
    expect(index.resolve_method("billing_closed?", "BoostInvite")).not_to be_nil
    expect(index.resolve_method("sync_state", "BoostInvite")).not_to be_nil
    expect(index.resolve_method("ready_sync_state?", "BoostInvite")).not_to be_nil
    expect(index.resolve_method("done_sync_state?", "BoostInvite")).not_to be_nil
  end

  it "combines prefix and suffix options like HasStateMachine::Machine" do
    index_source("/app/models/episode.rb", <<~RUBY)
      class Episode < ApplicationRecord
        has_state_machine states: %i[available removing],
          state_attribute: :deletion_state,
          prefix: true,
          suffix: :workflow
      end
    RUBY

    expect(index.resolve_method("deletion_state_available_workflow?", "Episode")).not_to be_nil
    expect(index.resolve_method("deletion_state_removing_workflow?", "Episode")).not_to be_nil
  end

  it "registers custom workflow_namespace strings, symbols, and constants" do
    index_source("/app/models/subscription.rb", <<~RUBY)
      class Subscription < ApplicationRecord
        STATES = %i[pending active]
        has_state_machine states: STATES
        has_state_machine states: %i[unset active inactive],
          state_attribute: :marketing_status,
          workflow_namespace: "Workflow::SubscriptionMarketing",
          prefix: :marketing
      end
    RUBY

    index_source("/app/models/beehiiv_mta/dkim_backfill.rb", <<~RUBY)
      module BeehiivMta
        class DkimBackfill < ApplicationRecord
          has_state_machine states: %i[pending completed],
            workflow_namespace: Workflow::DkimBackfill
        end
      end
    RUBY

    expect(registry.model_for("Workflow::SubscriptionMarketing")).to eq("Subscription")
    expect(registry.model_for("Workflow::DkimBackfill")).to eq("BeehiivMta::DkimBackfill")
    expect(index.resolve_method("status", "Subscription")).not_to be_nil
    expect(index.resolve_method("marketing_status", "Subscription")).not_to be_nil
    expect(index.resolve_method("marketing_active?", "Subscription")).not_to be_nil
  end

  it "ignores blank workflow_namespace values and module/concern owners" do
    index_source("/app/models/concerns/domain_configurable.rb", <<~RUBY)
      module DomainConfigurable
        extend ActiveSupport::Concern

        included do
          has_state_machine states: self::STATES,
            attribute: :status,
            workflow_namespace: "Workflow::ShouldNotRegister"
        end
      end
    RUBY

    index_source("/app/models/article.rb", <<~RUBY)
      class Article < ApplicationRecord
        has_state_machine states: %i[draft], workflow_namespace: " "
      end
    RUBY

    expect(registry.model_for("Workflow::ShouldNotRegister")).to be_nil
    expect(registry.model_for(" ")).to be_nil
    expect(index.resolve_method("status", "DomainConfigurable")).not_to be_nil
  end

  it "replaces stale namespace registrations when a file is re-indexed" do
    uri = index_source("/app/models/subscription.rb", <<~RUBY)
      class Subscription < ApplicationRecord
        has_state_machine states: %i[unset active],
          state_attribute: :marketing_status,
          workflow_namespace: "Workflow::OldMarketing"
      end
    RUBY

    expect(registry.model_for("Workflow::OldMarketing")).to eq("Subscription")

    index.handle_change(uri, <<~RUBY)
      class Subscription < ApplicationRecord
        has_state_machine states: %i[unset active],
          state_attribute: :marketing_status,
          workflow_namespace: "Workflow::NewMarketing"
      end
    RUBY

    expect(registry.model_for("Workflow::OldMarketing")).to be_nil
    expect(registry.model_for("Workflow::NewMarketing")).to eq("Subscription")
  end

  it "drops namespace registrations when a re-index removes the last has_state_machine call" do
    uri = index_source("/app/models/subscription.rb", <<~RUBY)
      class Subscription < ApplicationRecord
        has_state_machine states: %i[unset active], workflow_namespace: "Workflow::SubscriptionMarketing"
      end
    RUBY
    index_source("/app/models/post.rb", <<~RUBY)
      class Post < ApplicationRecord
        has_state_machine states: %i[draft], workflow_namespace: "Workflow::CustomPost"
      end
    RUBY

    index.handle_change(uri, <<~RUBY)
      class Subscription < ApplicationRecord
      end
    RUBY

    expect(registry.model_for("Workflow::SubscriptionMarketing")).to be_nil
    expect(registry.model_for("Workflow::CustomPost")).to eq("Post")
  end

  it "skips predicate indexing cleanly when states or affixes are dynamic" do
    index_source("/app/models/dynamic_model.rb", <<~RUBY)
      class DynamicModel < ApplicationRecord
        has_state_machine states: statuses.keys, state_attribute: :status
        has_state_machine states: %i[a b], state_attribute: :other_status, prefix: compute_prefix
      end
    RUBY

    expect(index.resolve_method("status", "DynamicModel")).not_to be_nil
    expect(index.resolve_method("other_status", "DynamicModel")).not_to be_nil
    expect(index.resolve_method("a?", "DynamicModel")).to be_nil
  end
end
