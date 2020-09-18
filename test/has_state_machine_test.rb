# frozen_string_literal: true

require "test_helper"

class HasStateMachine::Test < ActiveSupport::TestCase
  test "truth" do
    assert_kind_of Module, HasStateMachine
  end
end
