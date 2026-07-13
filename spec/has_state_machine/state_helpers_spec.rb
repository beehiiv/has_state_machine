# frozen_string_literal: true

ActiveRecord::Migration.create_table :mountains, force: true do |t|
  t.string :status
end

ActiveRecord::Migration.create_table :trees, force: true do |t|
  t.bigint :mountain_id
  t.string :status
end

ActiveRecord::Migration.create_table :animals, force: true do |t|
  t.string :status
end

class Mountain < ActiveRecord::Base
  has_state_machine states: %i[foo bar baz]
  has_many :trees
end

class Tree < ActiveRecord::Base
  has_state_machine states: %i[foo bar baz]
  belongs_to :mountain
end

class Animal < ActiveRecord::Base
  validate :failing_validation

  has_state_machine states: %i[foo bar baz]

  def failing_validation
    errors.add(:fail, "animal is not valid")
  end
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

  module Tree
    class Foo < HasStateMachine::State
    end
  end

  module Animal
    class Baz < HasStateMachine::State
      validate :failing_validation

      def failing_validation
        errors.add(:base, "dummy validation failed")
      end
    end
  end
end

RSpec.describe HasStateMachine::StateHelpers do
  subject { Mountain.new }

  describe "delegated methods" do
    it { expect(subject).to respond_to(:state_attribute) }
    it { expect(subject).to respond_to(:state_validations_on_object?) }
    it { expect(subject).to respond_to(:workflow_namespace) }
    it { expect(subject).to respond_to(:workflow_states) }
  end

  it "defaults instance to initial state" do
    expect(subject.status).to eq("foo")
  end

  describe "validations" do
    it "is valid if state attribute is a valid state" do
      subject.status = "foo"
      expect(subject).to be_valid
    end

    it "is invalid if state attribute is an invalid state" do
      subject.status = "random"
      expect(subject).not_to be_valid
    end

    it "is invalid if state does not have class defined" do
      subject.status = "bar"
      expect(subject).not_to be_valid
    end

    it "is invalid if state validations do not pass" do
      subject.status = "baz"
      expect(subject).not_to be_valid
    end

    it "ignores state validations if accessor is set" do
      subject.status = "baz"
      subject.skip_state_validations = true

      expect(subject).to be_valid
    end

    describe "object also contains errors" do
      subject { Animal.new }

      it "does not remove already existing errors from the object if state also has errors" do
        subject.status = "baz"
        expect(subject).not_to be_valid

        expect(subject.errors.to_a.length).to eq(2)
      end
    end
  end

  describe "state attribute method" do
    it "returns an instance of HasStateMachine::State" do
      expect(subject.status).to be_a(HasStateMachine::State)
    end
  end

  describe "generated predicate methods" do
    it { expect(subject).to be_foo }
    it { expect(subject).not_to be_bar }
    it { expect(subject).not_to be_baz }
  end

  describe "generated scopes" do
    it { expect(Mountain.foo).to be_a(ActiveRecord::Relation) }
    it { expect(Mountain.bar).to be_a(ActiveRecord::Relation) }
    it { expect(Mountain.foo).to be_a(ActiveRecord::Relation) }

    it "works correctly with joins" do
      foo_mountain = Mountain.create(status: "foo")
      bar_mountain = Mountain.create(status: "bar")
      Tree.create(mountain: foo_mountain, status: "foo")
      Tree.create(mountain: bar_mountain, status: "foo")

      expect(Mountain.foo.joins(:trees).merge(Tree.foo).to_a).to eq([foo_mountain])
    end
  end
end
