# frozen_string_literal: true

require "has_state_machine/railtie"
require "has_state_machine/core_ext/string"
require "has_state_machine/definition"
require "has_state_machine/deprecation"

module HasStateMachine
end

ActiveRecord::Base.include HasStateMachine::Definition if defined?(ActiveRecord)
