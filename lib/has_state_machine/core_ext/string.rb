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
  def transition_to(_desired_state)
    false
  end
end
