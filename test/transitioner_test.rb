# frozen_string_literal: true

require "test_helper"

class Transitioner::Test < ActiveSupport::TestCase
  test "truth" do
    assert_kind_of Module, Transitioner
  end
end
