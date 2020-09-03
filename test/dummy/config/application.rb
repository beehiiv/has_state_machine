# frozen_string_literal: true

require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)
require "transitioner"

module Dummy
  class Application < Rails::Application
  end
end
