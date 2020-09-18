# frozen_string_literal: true

require "test_helper"

ActiveRecord::Migration.create_table :foobars, force: true do |t|
  t.string :status
end

class Foobar < ActiveRecord::Base
  has_state_machine states: %i[foo bar]
end

class WorkflowTest < ActiveSupport::TestCase
  subject { Foobar.new }

  describe "#has_state_machine" do
    it "includes the correct module" do
      assert_includes subject.class.included_modules, HasStateMachine::StateHelpers
    end

    describe "helper methods" do
      describe "#workflow_states" do
        it { subject.respond_to? :workflow_states }

        it "returns the possible states" do
          assert_equal %w[foo bar], subject.workflow_states
        end
      end

      describe "#state_attribute" do
        it { subject.respond_to? :state_attribute }

        it "returns the correct value" do
          assert_equal :status, subject.state_attribute
        end
      end

      describe "#workflow_namespace" do
        it { subject.respond_to? :workflow_namespace }

        it "returns the correct value" do
          assert_equal "Workflow::Foobar", subject.workflow_namespace
        end
      end

      describe "#state_validations_on_object?" do
        it { subject.respond_to? :state_validations_on_object? }

        it "defaults to true" do
          assert subject.state_validations_on_object?
        end
      end
    end
  end
end
