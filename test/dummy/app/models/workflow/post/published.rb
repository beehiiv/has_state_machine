# frozen_string_literal: true

module Workflow
  class Post::Published < Workflow::Base
    state_options transitions_to: %i[archived]

    validate :title_exists?

    def title_exists?
      return if object.title.present?

      errors.add(:title, "can't be blank")
    end
  end
end
