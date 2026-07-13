# frozen_string_literal: true

require "bundler/gem_tasks"

task default: %i[lint test]

namespace :test do
  task :refresh do
    sh "bin/appraisal clean"
    sh "bin/appraisal generate"
  end

  task :all do
    sh "bin/appraisal install"
    sh "bin/appraisal bin/rake test"
  end
end

task :test do
  sh "bin/rspec"
end

task :lint do
  sh "bin/rubocop --no-server"
end

namespace :changelog do
  task :refresh do
    sh "bin/refresh_changelog"
  end
end
