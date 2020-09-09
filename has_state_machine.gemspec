$:.push File.expand_path("lib", __dir__)

require "has_state_machine/version"

Gem::Specification.new do |spec|
  spec.name = "has_state_machine"
  spec.version = HasStateMachine::VERSION
  spec.authors = ["Benjamin Hargett", "Jake Hurd"]
  spec.email = ["hargettbenjamin@gmail.com", "jake.hurd@gmail.com"]
  spec.homepage = "https://www.github.com/bharget/has_state_machine"
  spec.summary = "Class based state machine for ActiveRecord models."
  spec.description = "HasStateMachine uses ruby classes to make creating a finite state machine in your ActiveRecord models a breeze."
  spec.license = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => spec.homepage,
    "source_code_uri" => spec.homepage
  }

  spec.files = Dir["lib/**/*"]

  spec.required_ruby_version = ">= 2.5"

  spec.add_dependency "rails", ">= 5.2"

  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-rails"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "appraisal"
end
