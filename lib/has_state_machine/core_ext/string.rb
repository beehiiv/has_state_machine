# frozen_string_literal: true

class String
  ##
  # Adding our transition method to the default String class to prevent
  # exceptions while transitioning from an invalid state. This method
  # gets overwritten by valid HasStateMachine::State classes.
  #
  # @return [Boolean] false
  #
  # @example
  #   "some random string".transition_to("draft") #=> false
  # rubocop:disable Naming/PredicateMethod -- mirrors HasStateMachine::State#transition_to API
  def transition_to(_desired_state, **_options)
    false
  end
  # rubocop:enable Naming/PredicateMethod
end
