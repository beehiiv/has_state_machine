# frozen_string_literal: true

require "ruby_lsp/has_state_machine/rails_server_addon"

ActiveRecord::Migration.create_table :episodes, force: true do |t|
  t.string :title
  t.string :status
  t.string :deletion_state
  t.string :review_state
  t.timestamps
end

class Episode < ActiveRecord::Base
  attr_accessor :downloads_pending, :archive_on_decommission

  def events
    @events ||= []
  end

  has_state_machine states: %i[draft scheduled published archived unlisted]
  has_state_machine states: %i[available removing failed decommissioned],
    state_attribute: :deletion_state,
    workflow_namespace: "Workflow::EpisodeDeletion",
    prefix: :deletion
end

class ReviewedEpisode < Episode
  has_state_machine states: %i[unreviewed reviewed],
    state_attribute: :review_state,
    workflow_namespace: "Workflow::EpisodeReview",
    prefix: :review
end

module Workflow
  class EpisodeBase < HasStateMachine::State
    after_transition do
      object.events << [:after_transition, state_attribute, previous_state, state]
    end

    after_transition_commit do
      object.events << [:after_transition_commit, state_attribute, previous_state, state]
    end
  end

  module Episode
    class Draft < EpisodeBase
      state_options transitions_to: %i[scheduled published archived]
    end

    class Scheduled < EpisodeBase
      state_options transitions_to: %i[published], transactional: true
    end

    class Published < EpisodeBase
      state_options transitions_to: %i[archived]

      validate :title_present

      def title_present
        errors.add(:title, :blank) if object.title.blank?
      end
    end

    class Archived < EpisodeBase
    end

    # "unlisted" intentionally has no state class.
  end

  module EpisodeDeletion
    class Available < EpisodeBase
      state_options transitions_to: %i[removing failed]
    end

    class Removing < EpisodeBase
      state_options transitions_to: %i[failed decommissioned], transactional: true, transients: %i[rollback]

      after_transition do
        rollback_transition if rollback
      end
    end

    class Failed < EpisodeBase
      state_options transitions_to: %i[removing]
    end

    class Decommissioned < EpisodeBase
      state_options transactional: true

      validate :no_pending_downloads

      after_transition do
        object.status.transition_to(:archived) if object.archive_on_decommission
      end

      def no_pending_downloads
        errors.add(:base, "downloads are still pending") if object.downloads_pending
      end
    end
  end

  # ReviewedEpisode's first machine resolves its own default namespace.
  module ReviewedEpisode
    class Draft < Workflow::Episode::Draft
    end
  end

  module EpisodeReview
    class Unreviewed < EpisodeBase
      state_options transitions_to: %i[reviewed]
    end

    class Reviewed < EpisodeBase
    end
  end
end

RSpec.describe "Multiple state machines on one model" do
  # after_transition_commit semantics need real COMMITs, which the
  # transactional fixture wrapper never issues.
  self.use_transactional_tests = false

  after { Episode.delete_all }

  let(:episode) { Episode.create!(title: "Pilot") }

  def self.supports_deferred_commit_callbacks?
    ActiveRecord.version >= Gem::Version.new("7.2")
  end

  def build_model(&block)
    Class.new(ActiveRecord::Base) do
      self.table_name = "episodes"
      class_eval(&block)
    end
  end

  def persisted_columns(record)
    record.class.where(id: record.id).pick(:status, :deletion_state)
  end

  def commit_events(record)
    record.events.select { |event| event.first == :after_transition_commit }
  end

  describe "definitions" do
    it "registers one machine per state attribute, in declaration order" do
      expect(Episode.state_machine_definitions.keys).to eq(%i[status deletion_state])
      expect(Episode.state_machine_definitions.values).to all(be_a(HasStateMachine::Machine))
      expect(Episode.state_machine_definitions).to be_frozen
    end

    it "keeps the class-level readers pointing at the first machine" do
      expect(Episode.workflow_states).to eq(%w[draft scheduled published archived unlisted])
      expect(Episode.state_attribute).to eq(:status)
      expect(Episode.workflow_namespace).to eq("Workflow::Episode")
      expect(Episode.state_validations_on_object?).to be(true)
    end

    it "keeps the instance delegates pointing at the first machine" do
      expect(episode.workflow_states).to eq(Episode.workflow_states)
      expect(episode.state_attribute).to eq(:status)
      expect(episode.workflow_namespace).to eq("Workflow::Episode")
      expect(episode.send(:current_state)).to eq("draft")
      expect(episode.send(:state_class)).to eq(Workflow::Episode::Draft)
    end
  end

  describe "defaults" do
    it "starts a new record in the first state of each machine" do
      new_episode = Episode.new

      expect(new_episode.status).to eq("draft")
      expect(new_episode.deletion_state).to eq("available")
    end
  end

  describe "getters" do
    it "returns each machine's state from its own namespace" do
      expect(episode.status).to be_a(Workflow::Episode::Draft)
      expect(episode.deletion_state).to be_a(Workflow::EpisodeDeletion::Available)
    end

    it "exposes the machine a state belongs to" do
      expect(episode.status.state_attribute).to eq(:status)
      expect(episode.deletion_state.state_attribute).to eq(:deletion_state)
      expect(episode.deletion_state.state_machine).to equal(Episode.state_machine_definitions[:deletion_state])
    end

    it "resolves the machine of a state built directly from its namespace" do
      expect(Workflow::EpisodeDeletion::Available.new(episode).state_attribute).to eq(:deletion_state)
      expect(Workflow::Episode::Draft.new(episode).state_attribute).to eq(:status)
    end

    it "returns a plain string when a machine's state class is missing" do
      episode.status = "unlisted"

      expect(episode.status).to eq("unlisted")
      expect(episode.status).not_to be_a(HasStateMachine::State)
      expect(episode.deletion_state).to be_a(Workflow::EpisodeDeletion::Available)
    end
  end

  describe "transitions" do
    it "transitions the first machine without touching the second" do
      expect(episode.status.transition_to(:published)).to be(true)

      expect(episode.saved_changes.keys - ["updated_at"]).to eq(["status"])
      expect(persisted_columns(episode)).to eq(%w[published available])
      expect(episode.deletion_state).to be_a(Workflow::EpisodeDeletion::Available)
    end

    it "transitions the second machine without touching the first" do
      expect(episode.deletion_state.transition_to(:failed)).to be(true)

      expect(episode.saved_changes.keys - ["updated_at"]).to eq(["deletion_state"])
      expect(persisted_columns(episode)).to eq(%w[draft failed])
      expect(episode.status).to be_a(Workflow::Episode::Draft)
    end

    it "writes only its own column in a transactional transition" do
      expect(episode.status.transition_to(:scheduled)).to be(true)
      expect(persisted_columns(episode)).to eq(%w[scheduled available])

      expect(episode.deletion_state.transition_to(:removing)).to be(true)
      expect(persisted_columns(episode)).to eq(%w[scheduled removing])
    end

    it "transitions a state built directly on its own machine" do
      Workflow::EpisodeDeletion::Available.new(episode).transition_to(:failed)

      expect(persisted_columns(episode)).to eq(%w[draft failed])
    end

    it "checks possible transitions against the machine's own state" do
      expect(episode.deletion_state.can_transition?(:removing)).to be(true)
      expect(episode.deletion_state.can_transition?(:published)).to be(false)
      expect(episode.deletion_state.transition_to(:published)).to be(false)
      expect(persisted_columns(episode)).to eq(%w[draft available])
    end

    it "rolls back only the transitioning machine" do
      expect(episode.deletion_state.transition_to(:removing, rollback: true)).to be(false)

      expect(persisted_columns(episode)).to eq(%w[draft available])
    end

    it "reports the previous state of each machine" do
      episode.status.transition_to(:scheduled)
      episode.deletion_state.transition_to(:failed)
      episode.deletion_state.transition_to(:removing)

      expect(episode.events.select { |event| event.first == :after_transition }).to eq([
        [:after_transition, :status, "draft", "scheduled"],
        [:after_transition, :deletion_state, "available", "failed"],
        [:after_transition, :deletion_state, "failed", "removing"]
      ])
    end

    it "keeps the previous state when a callback transitions the other machine" do
      episode.deletion_state.transition_to(:removing)
      episode.archive_on_decommission = true

      expect(episode.deletion_state.transition_to(:decommissioned)).to be(true)

      expect(persisted_columns(episode)).to eq(%w[archived decommissioned])
      expect(commit_events(episode).last(2)).to contain_exactly(
        [:after_transition_commit, :status, "draft", "archived"],
        [:after_transition_commit, :deletion_state, "removing", "decommissioned"]
      )
    end
  end

  describe "after_transition_commit" do
    it "fires once, for the machine that transitioned" do
      episode.deletion_state.transition_to(:failed)

      expect(commit_events(episode)).to eq([[:after_transition_commit, :deletion_state, "available", "failed"]])
    end

    it "fires once for a transactional transition" do
      episode.status.transition_to(:scheduled)

      expect(commit_events(episode)).to eq([[:after_transition_commit, :status, "draft", "scheduled"]])
    end

    it "does not fire when the transition rolls back" do
      episode.deletion_state.transition_to(:removing, rollback: true)

      expect(commit_events(episode)).to be_empty
    end

    if supports_deferred_commit_callbacks?
      it "waits for the outermost transaction to commit" do
        ActiveRecord::Base.transaction do
          episode.deletion_state.transition_to(:removing)
          episode.status.transition_to(:published)
          expect(commit_events(episode)).to be_empty
        end

        expect(commit_events(episode)).to eq([
          [:after_transition_commit, :deletion_state, "available", "removing"],
          [:after_transition_commit, :status, "draft", "published"]
        ])
      end

      it "does not fire when the outermost transaction rolls back" do
        ActiveRecord::Base.transaction do
          episode.deletion_state.transition_to(:removing)
          episode.status.transition_to(:published)
          raise ActiveRecord::Rollback
        end

        expect(commit_events(episode)).to be_empty
      end
    end
  end

  describe "validations" do
    it "validates each machine's column against its own states" do
      episode.status = "removing"
      episode.deletion_state = "published"

      expect(episode).not_to be_valid
      expect(episode.errors.details[:status]).to include(a_hash_including(error: :inclusion))
      expect(episode.errors.details[:deletion_state]).to include(a_hash_including(error: :inclusion))
    end

    it "reports a missing state class on that machine's column only" do
      episode.status = "unlisted"

      expect(episode).not_to be_valid
      expect(episode.errors.details[:status]).to include(a_hash_including(error: :not_implemented))
      expect(episode.errors[:deletion_state]).to be_empty
    end

    it "runs the state validations of every machine" do
      episode.update_columns(deletion_state: "decommissioned")
      episode.downloads_pending = true

      expect(episode).not_to be_valid
      expect(episode.errors[:base]).to eq(["downloads are still pending"])
    end

    it "skips the state validations of every machine" do
      episode.update_columns(status: "published", title: nil, deletion_state: "decommissioned")
      episode.downloads_pending = true
      episode.skip_state_validations = true

      expect(episode).to be_valid
    end

    it "does not add errors for the other machine on an invalid transition" do
      episode.update_columns(deletion_state: "removing")
      episode.downloads_pending = true

      expect(episode.deletion_state.transition_to(:decommissioned)).to be(false)
      expect(episode.errors[:base]).to eq(["downloads are still pending"])
      expect(episode.errors[:status]).to be_empty

      episode.title = nil
      expect(episode.status.transition_to(:published)).to be(false)
      expect(episode.errors[:title]).to be_present
      expect(episode.errors[:deletion_state]).to be_empty
      expect(persisted_columns(episode)).to eq(%w[draft removing])
    end
  end

  describe "scopes and predicates" do
    let!(:removing) { Episode.create!(title: "Removing", deletion_state: "removing") }
    let!(:published) { Episode.create!(title: "Published", status: "published") }

    it "generates unprefixed helpers for the first machine" do
      expect(Episode.published).to eq([published])
      expect(published).to be_published
      expect(removing).to be_draft
    end

    it "generates prefixed helpers for a machine with prefix:" do
      expect(Episode.deletion_removing).to eq([removing])
      expect(removing).to be_deletion_removing
      expect(published).to be_deletion_available
      expect(Episode).not_to respond_to(:removing)
      expect(removing).not_to respond_to(:removing?)
    end

    it "uses the state attribute as the prefix for prefix: true" do
      model = build_model do
        has_state_machine states: %i[draft published]
        has_state_machine states: %i[available removing], state_attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion", prefix: true
      end

      expect(model).to respond_to(:deletion_state_removing)
      expect(model.new).to respond_to(:deletion_state_removing?)
    end

    it "uses the state attribute as the suffix for suffix: true" do
      model = build_model do
        has_state_machine states: %i[draft published]
        has_state_machine states: %i[available removing], state_attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion", suffix: true
      end

      expect(model.removing_deletion_state.pluck(:id)).to eq([removing.id])
      expect(model.find(removing.id)).to be_removing_deletion_state
      expect(model.new).to be_available_deletion_state
      expect(model).not_to respond_to(:removing)
      expect(model.new).not_to respond_to(:removing?)
    end

    [:deletion, "deletion"].each do |suffix|
      it "uses a custom #{suffix.class} suffix for scopes and predicates" do
        model = build_model do
          has_state_machine states: %i[draft published]
          has_state_machine states: %i[available removing], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion", suffix: suffix
        end

        expect(model.removing_deletion.pluck(:id)).to eq([removing.id])
        expect(model.find(removing.id)).to be_removing_deletion
      end
    end

    it "combines a custom prefix and suffix" do
      model = build_model do
        has_state_machine states: %i[draft published]
        has_state_machine states: %i[available removing], state_attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion", prefix: :deletion, suffix: :workflow
      end

      expect(model.deletion_removing_workflow.pluck(:id)).to eq([removing.id])
      expect(model.find(removing.id)).to be_deletion_removing_workflow
    end

    it "combines prefix: true and suffix: true using the state attribute" do
      model = build_model do
        has_state_machine states: %i[draft published]
        has_state_machine states: %i[available removing], state_attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion", prefix: true, suffix: true
      end

      expect(model.deletion_state_removing_deletion_state.pluck(:id)).to eq([removing.id])
      expect(model.find(removing.id)).to be_deletion_state_removing_deletion_state
    end

    [nil, false].each do |suffix|
      it "leaves helper names unchanged for suffix: #{suffix.inspect}" do
        model = build_model do
          has_state_machine states: %i[draft published]
          has_state_machine states: %i[available removing], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion", prefix: false, suffix: suffix
        end

        expect(model.removing.pluck(:id)).to eq([removing.id])
        expect(model.find(removing.id)).to be_removing
      end
    end

    it "skips suffixed scopes but keeps suffixed predicates with scopes: false" do
      model = build_model do
        has_state_machine states: %i[draft published]
        has_state_machine states: %i[available removing], state_attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion", suffix: :deletion, scopes: false
      end

      expect(model).not_to respond_to(:removing_deletion)
      expect(model.find(removing.id)).to be_removing_deletion
    end

    it "skips scopes but keeps predicates with scopes: false" do
      model = build_model do
        has_state_machine states: %i[draft published]
        has_state_machine states: %i[available removing], state_attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion", scopes: false
      end

      expect(model).not_to respond_to(:removing)
      expect(model.new).to be_available
    end
  end

  describe "definition-time errors" do
    it "rejects an empty declaration before registering a machine" do
      model = build_model {}

      expect { model.has_state_machine }.to raise_error(ArgumentError, /at least one state/)
      expect(model).not_to respond_to(:state_machine_definitions)
    end

    it "raises when a predicate would collide with another machine's" do
      expect do
        build_model do
          has_state_machine states: %i[draft archived]
          has_state_machine states: %i[available archived], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion"
        end
      end.to raise_error(ArgumentError, /instance method "archived\?"/)
    end

    it "raises when a predicate would collide with an existing method" do
      expect do
        build_model do
          has_state_machine states: %i[draft published]
          has_state_machine states: %i[available frozen], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion"
        end
      end.to raise_error(ArgumentError, /instance method "frozen\?"/)
    end

    it "raises when a scope would collide with an existing class method" do
      expect do
        build_model do
          def self.deletion_removing = nil

          has_state_machine states: %i[draft published]
          has_state_machine states: %i[available removing], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion", prefix: :deletion
        end
      end.to raise_error(ArgumentError, /class method "deletion_removing"/)
    end

    it "rejects colliding suffixed predicates even with scopes disabled" do
      expect do
        build_model do
          has_state_machine states: %i[draft archived], suffix: :workflow
          has_state_machine states: %i[available archived], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion", suffix: :workflow, scopes: false
        end
      end.to raise_error(ArgumentError, /instance method "archived_workflow\?"\. Pass prefix: or suffix:\./)
    end

    it "rejects a suffixed scope that collides with an existing class method" do
      expect do
        build_model do
          def self.removing_deletion = nil

          has_state_machine states: %i[draft published]
          has_state_machine states: %i[available removing], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion", suffix: :deletion
        end
      end.to raise_error(ArgumentError, /class method "removing_deletion"\. Pass prefix:, suffix:, or scopes: false\./)
    end

    it "leaves the model unchanged when a definition raises" do
      model = build_model { has_state_machine states: %i[draft archived] }

      expect do
        model.has_state_machine states: %i[archived], state_attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion"
      end.to raise_error(ArgumentError)
      expect(model.state_machine_definitions.keys).to eq([:status])
    end

    it "keeps 1.x behavior of overriding existing methods for the first machine" do
      model = build_model do
        def archived? = false

        has_state_machine states: %i[draft archived]
      end

      expect(model.new(status: "archived")).to be_archived
    end

    it "raises when two machines would share a workflow namespace" do
      expect do
        build_model do
          has_state_machine states: %i[draft published]
          has_state_machine states: %i[available removing], state_attribute: :deletion_state, prefix: :deletion
        end
      end.to raise_error(ArgumentError, /workflow namespace/)
    end

    it "treats a blank namespace as the default during conflict detection" do
      expect do
        build_model do
          has_state_machine states: %i[draft published]
          has_state_machine states: %i[available removing], state_attribute: :deletion_state,
            workflow_namespace: "", prefix: :deletion
        end
      end.to raise_error(ArgumentError, /workflow namespace/)
    end
  end

  describe "redeclaring a state attribute" do
    # e.g. a concern declares the machine and the including model declares it again.
    let(:model) do
      build_model do
        has_state_machine states: %i[draft published], attribute: :status, state_validations_on_object: false
        has_state_machine states: %i[draft published]
      end
    end

    it "replaces the configuration in place, as in 1.x" do
      expect(model.state_machine_definitions.keys).to eq([:status])
      expect(model.state_validations_on_object?).to be(true)
    end

    it "does not generate the validations again" do
      expect(model.validators_on(:status).map(&:class)).to eq([
        ActiveModel::Validations::InclusionValidator,
        ActiveRecord::Validations::PresenceValidator
      ])
      state_callbacks = %i[state_class_defined? state_instance_validations]
      expect(model._validate_callbacks.map(&:filter) & state_callbacks).to eq(state_callbacks)
      expect(model._validate_callbacks.count { |callback| state_callbacks.include?(callback.filter) }).to eq(2)
    end

    it "resolves states through the latest declaration" do
      model = build_model do
        has_state_machine states: %i[draft published], workflow_namespace: "Workflow::Nowhere"
        has_state_machine states: %i[draft published], workflow_namespace: "Workflow::Episode"
      end

      expect(model.new.status).to be_a(Workflow::Episode::Draft)
    end

    it "still rejects a namespace shared with another machine" do
      expect do
        build_model do
          has_state_machine states: %i[draft published], workflow_namespace: "Workflow::Episode"
          has_state_machine states: %i[available], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::EpisodeDeletion"
          has_state_machine states: %i[available], state_attribute: :deletion_state,
            workflow_namespace: "Workflow::Episode"
        end
      end.to raise_error(ArgumentError, /workflow namespace/)
    end
  end

  describe "options" do
    ["", " "].each do |namespace|
      it "resolves the default namespace and state classes for #{namespace.inspect}" do
        model = build_model {}
        stub_const("DefaultNamespaceEpisode", model)
        stub_const("Workflow::DefaultNamespaceEpisode", Workflow::Episode)
        model.has_state_machine states: %i[draft published], workflow_namespace: namespace

        expect(model.workflow_namespace).to eq("Workflow::DefaultNamespaceEpisode")
        expect(model.new.status).to be_a(Workflow::Episode::Draft)
      end
    end

    it "accepts attribute: as an alias for state_attribute:" do
      model = build_model do
        has_state_machine states: %i[draft published]
        has_state_machine states: %i[available removing], attribute: :deletion_state,
          workflow_namespace: "Workflow::EpisodeDeletion"
      end

      expect(model.state_machine_definitions.keys).to eq(%i[status deletion_state])
    end

    it "warns about, but ignores, unknown options" do
      allow(HasStateMachine::Deprecation).to receive(:warn)

      model = build_model { has_state_machine states: %i[draft published], colum: :status }

      expect(HasStateMachine::Deprecation).to have_received(:warn).with(/unknown option\(s\) :colum/)
      expect(model.state_attribute).to eq(:status)
    end
  end

  describe "inheritance" do
    it "allows a subclass to redeclare a machine without changing its parent" do
      child = Class.new(Episode)
      child.has_state_machine states: Episode.workflow_states, workflow_namespace: "Workflow::Episode",
        state_validations_on_object: false

      expect(child.state_validations_on_object?).to be(false)
      expect(child.new.status).to be_a(Workflow::Episode::Draft)
      expect(Episode.state_validations_on_object?).to be(true)
      expect(Episode.workflow_namespace).to eq("Workflow::Episode")
      expect(child.state_machine_definitions[:deletion_state])
        .to equal(Episode.state_machine_definitions[:deletion_state])
    end

    it "gives a subclass its parent's machines plus its own" do
      expect(ReviewedEpisode.state_machine_definitions.keys).to eq(%i[status deletion_state review_state])

      reviewed = ReviewedEpisode.create!(title: "Review me")
      expect(reviewed.review_state).to be_a(Workflow::EpisodeReview::Unreviewed)
      expect(reviewed.deletion_state).to be_a(Workflow::EpisodeDeletion::Available)
      expect(reviewed.review_state.transition_to(:reviewed)).to be(true)
      expect(reviewed.reload.review_state).to eq("reviewed")
      expect(ReviewedEpisode.review_reviewed).to eq([reviewed])
    end

    it "does not change the parent" do
      expect(Episode.state_machine_definitions.keys).to eq(%i[status deletion_state])
      expect(Episode).not_to respond_to(:review_reviewed)
      expect(Episode.new).not_to respond_to(:review_reviewed?)
      expect(Episode.new.review_state).to be_nil
      expect(Episode.new(review_state: "bogus")).to be_valid
    end

    it "resolves the default namespace against the subclass, as in 1.x" do
      reviewed = ReviewedEpisode.new

      expect(ReviewedEpisode.workflow_namespace).to eq("Workflow::ReviewedEpisode")
      expect(reviewed.status).to be_a(Workflow::ReviewedEpisode::Draft)
      expect(Workflow::ReviewedEpisode::Draft.new(reviewed).state_attribute).to eq(:status)
    end
  end

  describe "Ruby LSP Rails server add-on" do
    let(:stdout) { StringIO.new }
    let(:addon) { RubyLsp::HasStateMachine::RailsServerAddon.new(stdout, StringIO.new, {}) }

    it "resolves the model for a second machine's custom namespace" do
      addon.execute("model_for_workflow_namespace", {workflow_namespace: "Workflow::EpisodeDeletion"})

      result = JSON.parse(stdout.string.split("\r\n\r\n").last, symbolize_names: true)
      expect(result).to eq(result: {name: "Episode"})
    end
  end
end
