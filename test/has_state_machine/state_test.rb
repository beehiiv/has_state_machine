# frozen_string_literal: true

require "test_helper"

ActiveRecord::Migration.create_table :swimmers, force: true do |t|
  t.string :status
end

class Swimmer < ActiveRecord::Base
  attr_accessor :before_transition_boolean
  attr_accessor :after_transition_boolean
  attr_accessor :previous_state

  has_state_machine states: %i[diving swimming floating tanning tubing]
end

module Workflow
  module Swimmer
    class Diving < HasStateMachine::State
      state_options transitions_to: %i[swimming floating tanning tubing]
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
  end
end

class HasStateMachine::StateTest < ActiveSupport::TestCase
  let(:object) { Swimmer.create }
  subject { Workflow::Swimmer::Diving.new(object) }

  describe "#possible_transitions" do
    it { assert_equal %w[swimming floating tanning tubing], subject.possible_transitions }
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
      it "does not perform transition if after_transition rollsback" do
        refute subject.transition_to(:tanning)
        assert_equal "diving", object.reload.status
      end

      it "does not perform transition if before_transition rollsback" do
        refute subject.transition_to(:tubing)
        assert_equal "diving", object.reload.status
      end
    end
  end
end
