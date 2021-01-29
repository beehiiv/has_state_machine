# HasStateMachine

[![Build Status](https://github.com/bharget/has_state_machine/workflows/Tests/badge.svg)](https://github.com/bharget/has_state_machine/actions)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)

HasStateMachine uses ruby classes to make creating a finite state machine for your ActiveRecord models a breeze.

## Contents

- [HasStateMachine](#hasstatemachine)
  - [Contents](#contents)
  - [Installation](#installation)
  - [Usage](#usage)
    - [Advanced Usage](#advanced-usage)
  - [Contributing](#contributing)
  - [License](#license)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'has_state_machine'
```

And then execute:

```bash
$ bundle
```

Or install it yourself as:

```bash
$ gem install has_state_machine
```

## Usage

You must first use the `has_state_machine` macro to define your state machine at
a high level. This includes defining the possible states for your object as well
as some optional configuration should you want to change the default behavior of
the state machine.

```ruby
# By default, it is assumed that the "state" of the object is
# stored in a string column named "status".
class Post < ApplicationRecord
  has_state_machine states: %i[draft published archived]
end
```

Now you must define the classes for the states in your state machine. By default,
`HasStateMachine` assumes that these will be under the `Workflow` namespace following
the pattern of `Workflow::#{ObjectClass}::#{State}`. The state objects must inherit
from `HasStateMachine::State`.

```ruby
module Workflow
  class Post::Draft < HasStateMachine::State
    # Define the possible transitions from the "draft" state
    state_options transitions_to: %i[published archived]
  end
end

module Workflow
  class Post::Published < HasStateMachine::State
    state_options transitions_to: %i[archived]

    # Custom validations can be added to the state to ensure a transition is "valid"
    validate :title_exists?

    def title_exists?
      return if object.title.present?

      # Errors get added to the ActiveRecord object
      errors.add(:title, "can't be blank")
    end
  end
end

module Workflow
  class Post::Archived < HasStateMachine::State
    # There are callbacks for running logic before and after
    # a transition occurs.
    before_transition do
      Rails.logger.info "== Post is being archived ==\n"
    end

    after_transition do
      Rails.logger.info "== Post has been archived ==\n"

      # You can access the previous state of the object in
      # after_transition callbacks as well.
      Rails.logger.info "== Transitioned from #{previous_state} ==\n"
    end
  end
end
```

Some examples:

```ruby
post = Post.create(status: "draft")

post.status.transition_to(:published) # => false
post.status                           # => "draft"

post.title = "Foobar"
post.status.transition_to(:published) # => true
post.status                           # => "published"

post.status.transition_to(:archived)
# == Post is being archived ==
# == Post has been archived ==
# == Transitioned from published ==
# => true
```

### Advanced Usage

Sometimes there may be a situation where you want to manually roll back a state change in one of the provided callbacks. To do this, add the `transactional: true` option to the `state_options` declaration and use the `rollback_transition` method in your callback. This will allow you to prevent the transition from persisting if something further down the line fails.

```ruby
module Workflow
  class Post::Archived < HasStateMachine::State
    state_options transactional: true

    after_transition do
      rollback_transition unless notified_watchers?
    end

    private

    def notified_watchers?
      #...
    end
  end
end
```

## Contributing

Anyone is encouraged to help improve this project. Here are a few ways you can help:

- [Report bugs](https://github.com/encampment/has_state_machine/issues)
- Fix bugs and [submit pull requests](https://github.com/encampment/has_state_machine/pulls)
- Write, clarify, or fix documentation
- Suggest or add new features

To get started with development:

```
git clone https://github.com/encampment/has_state_machine.git
cd has_state_machine
bundle install
bundle exec rake test
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
