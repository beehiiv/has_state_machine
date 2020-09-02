# frozen_string_literal: true

module Workflow
  class Post::Published < Workflow::Base
    transitions_to %i[archived]

    validate :title_exists?

    def title_exists?
      return if object.title.present?

      object.errors.add(:title, "can't be blank")
    end
  end
end
