# frozen_string_literal: true

require "test_helper"

ActiveRecord::Migration.create_table :mountains, force: true do |t|
  t.string :status
end

class Mountain < ActiveRecord::Base
  has_state_machine states: %i[foo bar baz]
end

module Workflow
  module Mountain
    class Foo < HasStateMachine::State
    end

    class Baz < HasStateMachine::State
      validate :failing_validation

      def failing_validation
        errors.add(:base, "dummy validation failed")
      end
    end
  end
end

class HasStateMachine::StateHelpersTest < ActiveSupport::TestCase
  subject { Mountain.new }

  describe "delegated methods" do
    it { assert subject.respond_to? :state_attribute }
    it { assert subject.respond_to? :state_validations_on_object? }
    it { assert subject.respond_to? :workflow_namespace }
    it { assert subject.respond_to? :workflow_states }
  end

  it "defaults instance to initial state" do
    assert_equal "foo", subject.status
  end

  describe "validations" do
    it "is valid if state attribute is a valid state" do
      subject.status = "foo"
      assert subject.valid?
    end

    it "is invalid if state attribute is an invalid state" do
      subject.status = "random"
      refute subject.valid?
    end

    it "is invalid if state does not have class defined" do
      subject.status = "bar"
      refute subject.valid?
    end

    it "is invalid if state validations do not pass" do
      subject.status = "baz"
      refute subject.valid?
    end

    it "ignores state validations if accessor is set" do
      subject.status = "baz"
      subject.skip_state_validations = true

      assert subject.valid?
    end
  end

  describe "state attribute method" do
    it "it returns an instance of HasStateMachine::State" do
      assert_kind_of HasStateMachine::State, subject.status
    end
  end

  describe "generated predicate methods" do
    it { assert subject.foo? }
    it { refute subject.bar? }
    it { refute subject.baz? }
  end

  describe "generated scopes" do
    it { assert_kind_of ActiveRecord::Relation, Mountain.foo }
    it { assert_kind_of ActiveRecord::Relation, Mountain.bar }
    it { assert_kind_of ActiveRecord::Relation, Mountain.foo }
  end
end
