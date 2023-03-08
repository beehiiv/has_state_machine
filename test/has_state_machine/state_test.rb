# frozen_string_literal: true

require "test_helper"

ActiveRecord::Migration.create_table :swimmers, force: true do |t|
  t.string :status
  t.boolean :needs_lotion_before, default: true
  t.boolean :needs_lotion_after, default: true
end

class Swimmer < ActiveRecord::Base
  attr_accessor :before_transition_boolean
  attr_accessor :after_transition_boolean
  attr_accessor :previous_state

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
      state_options transactional: true

      before_transition do
        rollback_transition unless object.needs_lotion_before
      end

      after_transition do
        rollback_transition unless object.needs_lotion_after
      end
    end
  end
end

class HasStateMachine::StateTest < ActiveSupport::TestCase
  let(:object) { Swimmer.create }
  subject { Workflow::Swimmer::Diving.new(object) }

  describe "#possible_transitions" do
    it { assert_equal %w[swimming floating tanning tubing lotioning], subject.possible_transitions }
  end

  describe "#errors" do
    it "delegates to the object" do
      object.errors.add(:base, "foobar")

      assert_equal({base: %w[foobar]}, subject.errors.messages)
    end
  end

  describe "#transition_to" do
    describe "callbacks" do
      it "runs before_transition callbacks" do
        refute object.before_transition_boolean
        subject.transition_to(:swimming)
        assert object.before_transition_boolean
      end

      it "runs after_transition callbacks" do
        refute object.after_transition_boolean
        subject.transition_to(:swimming)
        assert object.after_transition_boolean
      end

      it "has access to the previous state" do
        assert object.previous_state.nil?
        subject.transition_to(:swimming)
        assert_equal "diving", object.previous_state
      end
    end

    it "updates the object's state attribute" do
      assert_equal "diving", object.status

      subject.transition_to(:swimming)

      assert_equal "swimming", object.status
    end

    it "fails if transitioning to an invalid state" do
      refute subject.transition_to(:running)
      assert_equal "diving", object.status
    end

    it "fails if state validations fail" do
      refute subject.transition_to(:floating)
      assert_equal "diving", object.status
    end

    it "can skip state validations" do
      assert subject.transition_to(:floating, skip_validations: true)
      assert_equal "floating", object.status
    end

    describe "transactional" do
      it "does not perform transition if after_transition rolls back" do
        refute subject.transition_to(:tanning)
        assert_equal "diving", object.reload.status
      end

      it "does not perform transition if before_transition rolls back" do
        refute subject.transition_to(:tubing)
        assert_equal "diving", object.reload.status
      end

      it "returns true if the transaction is successfull" do
        object.update(status: "diving", needs_lotion_before: true, needs_lotion_after: true)
        assert_equal true, subject.transition_to(:lotioning)
        assert_equal "lotioning", object.reload.status.to_s
      end

      it "returns false if the transaction is rolled back in the after_transition" do
        object.update(status: "diving", needs_lotion_before: true, needs_lotion_after: false)
        assert_equal false, subject.transition_to(:lotioning)
        assert_equal "diving", object.reload.status.to_s
      end

      it "returns false if the transaction is rolled back in the before_transition" do
        object.update(status: "diving", needs_lotion_before: false, needs_lotion_after: true)
        assert_equal false, subject.transition_to(:lotioning)
        assert_equal "diving", object.reload.status.to_s
      end
    end
  end
end
