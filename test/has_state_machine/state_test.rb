# frozen_string_literal: true

require "test_helper"

ActiveRecord::Migration.create_table :swimmers, force: true do |t|
  t.string :status
end

class Swimmer < ActiveRecord::Base
  attr_accessor :before_transition_boolean
  attr_accessor :after_transition_boolean

  has_state_machine states: %i[diving swimming floating]
end

module Workflow
  module Swimmer
    class Diving < HasStateMachine::State
      transitions_to %i[swimming floating]
    end

    class Swimming < HasStateMachine::State
      before_transition do
        object.before_transition_boolean = true
      end

      after_transition do
        object.after_transition_boolean = true
      end
    end

    class Floating < HasStateMachine::State
      validate :can_float?

      def can_float?
        errors.add(:base, "swimmer cannot float")
      end
    end
  end
end

class HasStateMachine::StateTest < ActiveSupport::TestCase
  let(:object) { Swimmer.new }
  subject { Workflow::Swimmer::Diving.new(object) }

  describe "#possible_transitions" do
    it { assert_equal %w[swimming floating], subject.possible_transitions }
  end

  describe "#errors" do
    it "delegates to the object" do
      object.errors.add(:base, "foobar")

      assert_equal({base: %w[foobar]}, subject.errors.messages)
    end
  end

  describe "#transition_to" do
    it "runs callbacks" do
      refute object.before_transition_boolean
      refute object.after_transition_boolean

      subject.transition_to(:swimming)

      assert object.before_transition_boolean
      assert object.after_transition_boolean
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
  end
end
