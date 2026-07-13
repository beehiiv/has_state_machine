# frozen_string_literal: true

ActiveRecord::Migration.create_table :hikers, force: true do |t|
  t.string :status
end

class Hiker < ActiveRecord::Base
  has_state_machine states: %i[foo bar]
end

RSpec.describe HasStateMachine::Definition do
  subject { Hiker.new }

  describe "#has_state_machine" do
    it "includes the correct module" do
      expect(subject.class.included_modules).to include(HasStateMachine::StateHelpers)
    end

    describe "helper methods" do
      describe "#workflow_states" do
        it { expect(subject).to respond_to(:workflow_states) }

        it "returns the possible states" do
          expect(subject.workflow_states).to eq(%w[foo bar])
        end
      end

      describe "#state_attribute" do
        it { expect(subject).to respond_to(:state_attribute) }

        it "returns the correct value" do
          expect(subject.state_attribute).to eq(:status)
        end
      end

      describe "#workflow_namespace" do
        it { expect(subject).to respond_to(:workflow_namespace) }

        it "returns the correct value" do
          expect(subject.workflow_namespace).to eq("Workflow::Hiker")
        end
      end

      describe "#state_validations_on_object?" do
        it { expect(subject).to respond_to(:state_validations_on_object?) }

        it "defaults to true" do
          expect(subject.state_validations_on_object?).to be(true)
        end
      end
    end
  end
end
