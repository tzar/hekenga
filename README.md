# Hekenga

A migration framework for MongoDB (via Mongoid) that supports parallel document
processing via ActiveJob, chained jobs, and error recovery.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hekenga'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install hekenga

## Configuration

```ruby
Hekenga.configure do |config|
  config.dir  = ["db", "hekenga"] # where migration files live (relative to root)
  config.root = Dir.pwd           # application root
end
```

Migrations are stored as Ruby files in the configured directory (default: `db/hekenga/`).

## Usage

### CLI

```
$ hekenga help                          # Show all available commands
$ hekenga generate <description>        # Generate a new migration scaffold
$ hekenga status                        # Show status of all migrations
$ hekenga run_all!                      # Run all pending migrations in date order
$ hekenga run! <path_or_pkey>           # Run a specific migration
$ hekenga run! <path_or_pkey> --test    # Dry run (no writes persisted)
$ hekenga run! <path_or_pkey> --clear   # Clear logs before running
$ hekenga recover! <path_or_pkey>       # Re-process failed/invalid records
$ hekenga cancel                        # Cancel all active migrations
$ hekenga skip <path_or_pkey>           # Mark a migration as skipped
$ hekenga clear! <path_or_pkey>         # Remove all logs/failures for a migration
$ hekenga cleanup                       # Remove all failure logs
```

### Writing Migrations

Generate a migration scaffold:

    $ hekenga generate "Add default role to users"

#### Simple Tasks

Simple tasks run arbitrary code once. Use `actual?` and `test?` to check execution mode.

```ruby
Hekenga.migration do
  description "Backfill analytics collection"
  created "2024-01-15 10:00"

  task "Create indexes" do
    up do
      Analytics.create_indexes if actual?
    end
  end
end
```

#### Document Tasks

Document tasks iterate over a Mongoid scope and process each document in batches.

```ruby
Hekenga.migration do
  description "Normalize user emails"
  created "2024-01-15 10:00"
  batch_size 100 # default batch size for all tasks in this migration

  per_document "Downcase emails" do
    scope User.all

    # Called once per batch; instance variables are shared with filter/up/after
    setup do |docs|
      @domain_map = ExternalService.load_domains
    end

    # Return false to skip a document
    filter do |doc|
      doc.email.present?
    end

    # Mutate the document in place — Hekenga handles persistence
    up do |doc|
      doc.email = doc.email.downcase
    end

    # Called once per batch with the successfully written documents
    after do |docs|
      AuditLog.record(docs.map(&:id))
    end
  end
end
```

#### Document Task Options

```ruby
per_document "Process records" do
  scope MyModel.where(active: true)

  parallel!                           # Process batches in parallel via ActiveJob
  timeless!                           # Don't update Mongoid timestamps
  always_write!                       # Write even if the document didn't change
  skip_prepare!                       # Skip Mongoid callbacks on load
  use_transaction!                    # Wrap each batch in a MongoDB transaction
  batch_size 50                       # Override migration-level batch size
  write_strategy :update              # :update (default) or :delete_then_insert
  cursor_timeout 86_400               # Max cursor lifetime in seconds (default: 1 day)

  up do |doc|
    doc.status = "migrated"
  end
end
```

### Test Mode

Run a migration without persisting changes:

```ruby
migration = Hekenga.find_migration("2024-01-15-add-default-role-to-users")
migration.test_mode!
migration.perform!
```

Or via the CLI:

    $ hekenga run! <path_or_pkey> --test

### Recovery

When a migration fails (due to errors, invalid records, or write failures), Hekenga logs the failures and marks the migration as failed. You can re-process only the failed records:

    $ hekenga recover! <path_or_pkey>

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tzar/hekenga.
