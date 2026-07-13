# HasStateMachine

[![CI](https://github.com/beehiiv/has_state_machine/actions/workflows/ci.yml/badge.svg)](https://github.com/beehiiv/has_state_machine/actions/workflows/ci.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)

HasStateMachine uses ruby classes to make creating a finite state machine for your ActiveRecord models a breeze.

## Contents

- [HasStateMachine](#hasstatemachine)
  - [Contents](#contents)
  - [Installation](#installation)
  - [Usage](#basic-usage)
    - [Basic Usage](#basic-usage)
    - [Validations & Error Handling](#validations-and-error-handling)
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

## Basic Usage

You must first use the `has_state_machine` macro to define your state machine at
a high level. This includes defining the possible states for your object as well
as some optional configuration should you want to change the default behavior of
the state machine (more on this later).

```ruby
# By default, it is assumed that the "state" of the object is
# stored in a string column named "status".
class Post < ApplicationRecord
  has_state_machine states: %i[draft published archived]
end
```

Now you must define the classes for the states in your state machine. By default,
`HasStateMachine` assumes that these will be under the `Workflow` namespace following
the pattern of `Workflow::#{ObjectClass}::#{State}`. The state classes must inherit
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

    # after_transition_commit runs only once the transition has been
    # committed: after the record is saved for normal transitions, and
    # outside the transaction for transactional transitions (see below).
    after_transition_commit do
      MyJob.perform_later(object)
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

If you'd like to check that an object can be transitioned into a new state, use the `can_transition?` method. This checks to see if the provided argument is in the `transitions_to` array defined on the object's current state. (This does not run any validations that may be defined on the new state)

Example:
```ruby
post = Post.create(status: "draft")

post.status.can_transition?(:published) # => true
post.status.can_transition?(:other_state) # => false
```

### Validations and Error Handling

You can define custom validations on a given state to determine whether an object in that state or a transition to that state is valid.

By default, validations defined on the state will be run as part of the object validations if the object is in that state.

```ruby
post = Post.create(status: "published", title: "Title")

post.valid?
# => true

post.title = nil
post.valid?
# => false
```

If you wish to change this behavior and not have the state validations run on the object, you can specify that with the `state_validations_on_object` option when defining your state machine.

```ruby
class Post < ApplicationRecord
  has_state_machine states: %i[draft published, archived], state_validations_on_object: false
end

post = Post.create(status: "published", title: "Title")

post.valid?
# => true

post.title = nil
post.valid?
# => true
```

By default, when attempting to transition an object to another state, it checks:
  * Validations defined on the object
  * That the new state is one of the allowed transitions from the current state
  * Any validations defined on the new state

If any are found to be invalid, the transition will fail. Any errors from validations on the new state will be added to the object.

```ruby
post = Post.create(status: "draft")

post.title = nil
post.status.transition_to(:published)
# => false

post.errors.full_messages
# => ["Title can't be blank"]
```

If you wish to bypass this behavior and skip validations during a transition, you can do that:

```ruby
post = Post.create(status: "draft")

post.title = nil
post.status.transition_to(:published, skip_validations: true)
# => true
```

### Advanced Usage

#### Transactional Transitions

There may be a situation where you want to manually rollback a state change in one of the provided transition callbacks. To do this, add the `transactional: true` option to the `state_options` declaration. This results in the transition being wrapped in a transaction. You can then use the `rollback_transition` method in your callback when you want to trigger a rollback of the transaction. This will allow you to prevent the transition from persisting if something further down the line fails.

```ruby
module Workflow
  class Post::Archived < HasStateMachine::State
    state_options transactional: true

    after_transition do
      rollback_transition unless notified_watchers?
    end

    after_transition_commit do
      enqueue_external_work
    end

    private

    def enqueue_external_work
      # Any work you want to happen only after the transition is committed.
      # Enqueuing a job, calling an external API, sending a webhook, etc.
    end

    def notified_watchers?
      # Any dependent work that you want to run that should play a part in determining
      # whether the transition was successful or not and needs to be rolled back.
    end
  end
end
```

#### Transient Transition Variables

Sometimes you may may want to pass additional arguments to a state transition for additional context in your transition callbacks. To do this, add the `transients` option to the `state_options` declaration. This allows you to define any additional attributes you want to be able to pass along during a state transition to that state.

```ruby
module Workflow
  class Post::Archived < HasStateMachine::State
    state_options transients: %i[user]

    after_transition do
      puts "== Post archived by #{user.name} =="
    end
  end
end

current_user = User.create(name: "John Doe")
post = Post.create(status: "published")

post.status.transition_to(:archived, user: current_user)
# == Post archived by John Doe ==
# => true
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
