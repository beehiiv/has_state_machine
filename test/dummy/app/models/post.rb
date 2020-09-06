# frozen_string_literal: true

class Post < ApplicationRecord
  has_state_machine states: %i[draft published archived]
end
