# frozen_string_literal: true

module Workflow
  class Post::Draft < Workflow::Base
    transitions_to %i[published archived]
  end
end
