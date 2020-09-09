$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "has_state_machine/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name = "has_state_machine"
  spec.version = HasStateMachine::VERSION
  spec.authors = ["Benjamin Hargett"]
  spec.email = ["hargettbenjamin@gmail.com"]
  spec.homepage = "https://www.github.com/bharget/has_state_machine"
  spec.summary = "Class based state machine for ActiveRecord models."
  spec.description = "HasStateMachine uses ruby classes to make creating a finite state machine in your ActiveRecord models a breeze."
  spec.license = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.required_ruby_version = ">= 2.5"

  spec.add_dependency "rails", ">= 5.2"

  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-rails"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "appraisal"
end