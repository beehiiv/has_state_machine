# frozen_string_literal: true

require "transitioner/railtie"
require "transitioner/core_ext/string"
require "transitioner/has_state_machine"

module Transitioner
end

ActiveRecord::Base.include Transitioner::HasStateMachine if defined?(ActiveRecord)
