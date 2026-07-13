# frozen_string_literal: true

ActiveRecord::Migration.create_table :swimmers, force: true do |t|
  t.string :status
end

class Swimmer < ActiveRecord::Base
  attr_accessor :before_transition_boolean
  attr_accessor :after_transition_boolean
  attr_accessor :after_transition_commit_boolean
  attr_accessor :previous_state
  attr_accessor :previous_state_in_commit
  attr_writer :callback_sequence

  def callback_sequence
    @callback_sequence ||= []
  end

  has_state_machine states: %i[diving swimming floating tanning tubing lotioning]
end

module Workflow
  module Swimmer
    class Diving < HasStateMachine::State
      state_options transitions_to: %i[swimming floating tanning tubing lotioning]
    end

    class Swimming < HasStateMachine::State
      before_transition do
        object.before_transition_boolean = true
      end

      after_transition do
        object.after_transition_boolean = true
        object.previous_state = previous_state
        object.callback_sequence << :after_transition
      end

      after_transition_commit do
        object.after_transition_commit_boolean = true
        object.previous_state_in_commit = previous_state
        object.callback_sequence << :after_transition_commit
      end
    end

    class Floating < HasStateMachine::State
      validate :can_float?

      def can_float?
        errors.add(:base, "swimmer cannot float")
      end
    end

    class Tubing < HasStateMachine::State
      state_options transactional: true

      before_transition do
        rollback_transition
      end
    end

    class Tanning < HasStateMachine::State
      state_options transactional: true

      after_transition do
        rollback_transition
      end
    end

    class Lotioning < HasStateMachine::State
      state_options transactional: true, transients: %i[needs_lotion_before needs_lotion_after]

      before_transition do
        rollback_transition unless needs_lotion_before
      end

      after_transition do
        rollback_transition unless needs_lotion_after
      end

      after_transition_commit do
        object.after_transition_commit_boolean = true
        object.previous_state_in_commit = previous_state
      end
    end
  end
end

RSpec.describe HasStateMachine::State do
  let(:object) { Swimmer.create }
  subject { Workflow::Swimmer::Diving.new(object) }

  describe "#possible_transitions" do
    it { expect(subject.possible_transitions).to eq(%w[swimming floating tanning tubing lotioning]) }
  end

  describe "#can_transition?" do
    describe "when the state is a string" do
      it "returns true if the transition is valid" do
        expect(subject.can_transition?("swimming")).to be(true)
      end

      it "returns false if the transition is invalid" do
        expect(subject.can_transition?("running")).to be(false)
      end
    end

    describe "when the state is a symbol" do
      it "returns true if the transition is valid" do
        expect(subject.can_transition?(:swimming)).to be(true)
      end

      it "returns false if the transition is invalid" do
        expect(subject.can_transition?(:running)).to be(false)
      end
    end
  end

  describe "#transition_to" do
    describe "callbacks" do
      it "runs before_transition callbacks" do
        expect(object.before_transition_boolean).to be_falsey
        subject.transition_to(:swimming)
        expect(object.before_transition_boolean).to be(true)
      end

      it "runs after_transition callbacks" do
        expect(object.after_transition_boolean).to be_falsey
        subject.transition_to(:swimming)
        expect(object.after_transition_boolean).to be(true)
      end

      it "has access to the previous state" do
        expect(object.previous_state).to be_nil
        subject.transition_to(:swimming)
        expect(object.previous_state).to eq("diving")
      end

      it "runs after_transition_commit callbacks" do
        expect(object.after_transition_commit_boolean).to be_falsey
        subject.transition_to(:swimming)
        expect(object.after_transition_commit_boolean).to be(true)
      end

      it "runs after_transition_commit after after_transition" do
        subject.transition_to(:swimming)
        expect(object.callback_sequence).to eq(%i[after_transition after_transition_commit])
      end

      it "has access to the previous state in after_transition_commit" do
        expect(object.previous_state_in_commit).to be_nil
        subject.transition_to(:swimming)
        expect(object.previous_state_in_commit).to eq("diving")
      end

      it "does not run after_transition_commit on an invalid transition" do
        expect(subject.transition_to(:running)).to be_falsey
        expect(object.after_transition_commit_boolean).to be_falsey
      end

      it "does not run after_transition_commit when state validations fail" do
        expect(subject.transition_to(:floating)).to be_falsey
        expect(object.after_transition_commit_boolean).to be_falsey
      end
    end

    it "updates the object's state attribute" do
      expect(object.status).to eq("diving")

      subject.transition_to(:swimming)

      expect(object.status).to eq("swimming")
    end

    it "fails if transitioning to an invalid state" do
      expect(subject.transition_to(:running)).to be_falsey
      expect(object.status).to eq("diving")
    end

    it "fails if state validations fail" do
      expect(subject.transition_to(:floating)).to be_falsey
      expect(object.status).to eq("diving")
    end

    it "can skip state validations" do
      expect(subject.transition_to(:floating, skip_validations: true)).to be_truthy
      expect(object.status).to eq("floating")
    end

    describe "transactional" do
      it "does not perform transition if after_transition rolls back" do
        expect(subject.transition_to(:tanning)).to be_falsey
        expect(object.reload.status).to eq("diving")
      end

      it "does not perform transition if before_transition rolls back" do
        expect(subject.transition_to(:tubing)).to be_falsey
        expect(object.reload.status).to eq("diving")
      end

      describe "with transients" do
        it "returns true if the transaction is successfull" do
          expect(subject.transition_to(:lotioning, needs_lotion_before: true, needs_lotion_after: true)).to be(true)
          expect(object.reload.status.to_s).to eq("lotioning")
        end

        it "returns false if the transaction is rolled back in the after_transition" do
          expect(subject.transition_to(:lotioning, needs_lotion_before: true, needs_lotion_after: false)).to be(false)
          expect(object.reload.status.to_s).to eq("diving")
        end

        it "returns false if the transaction is rolled back in the before_transition" do
          expect(subject.transition_to(:lotioning, needs_lotion_before: false, needs_lotion_after: true)).to be(false)
          expect(object.reload.status.to_s).to eq("diving")
        end

        it "runs after_transition_commit when the transaction commits" do
          subject.transition_to(:lotioning, needs_lotion_before: true, needs_lotion_after: true)
          expect(object.after_transition_commit_boolean).to be(true)
        end

        it "does not run after_transition_commit when rolled back in the after_transition" do
          subject.transition_to(:lotioning, needs_lotion_before: true, needs_lotion_after: false)
          expect(object.after_transition_commit_boolean).to be_falsey
        end

        it "does not run after_transition_commit when rolled back in the before_transition" do
          subject.transition_to(:lotioning, needs_lotion_before: false, needs_lotion_after: true)
          expect(object.after_transition_commit_boolean).to be_falsey
        end

        it "has access to the previous state in after_transition_commit" do
          subject.transition_to(:lotioning, needs_lotion_before: true, needs_lotion_after: true)
          expect(object.previous_state_in_commit).to eq("diving")
        end
      end
    end
  end
end
