# Hekenga

An attempt at a migration framework for MongoDB that supports parallel document
processing via ActiveJob, chained jobs and error recovery.

**Note that this gem is currently in pre-alpha - assume most things have a high
chance of being broken.**

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hekenga'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install hekenga

## Usage

CLI instructions:

    $ hekenga help

Migration DSL documentation TBD, for now please look at spec/

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tzar/hekenga.
