# frozen_string_literal: true

module Workflow
  class Post::Archived < Workflow::Base
    transitions_to %i[published]
  end
end
