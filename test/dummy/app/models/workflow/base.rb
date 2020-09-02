# frozen_string_literal: true

module Workflow
  class Base < Transitioner::State
    before_transition do
      Rails.logger.info "\nTransitioning..."
    end

    after_transition do
      Rails.logger.info "\nDone Transitioning!"
    end
  end
end
