# frozen_string_literal: true

module Workflow
  class Post::Archived < Workflow::Base
    state_options transitions_to: %i[published]
  end
end
