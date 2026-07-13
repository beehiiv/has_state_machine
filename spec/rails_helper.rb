# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [File.expand_path("../test/dummy/db/migrate", __dir__)]

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "pry"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.fixture_paths = [File.expand_path("fixtures", __dir__)] if config.respond_to?(:fixture_paths=)
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
