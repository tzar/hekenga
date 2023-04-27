# Changelog

## v1.0.1

- Generate migrations without : in the filename for windows

## v1.0.0

- `hekenga run!` now has a `--clear` option to clear the migration prior to running it
- (breaking) `per_document` tasks now generate `Hekenga::DocumentTaskRecord`, used for
    recovery + progress tracking. `Hekenga::Failure::Cancelled` and
    `Hekenga::Failure::Validation` are no longer generated.
- (breaking) Migrations will now always continue when encountering invalid records.
    Recovering the migration later will reprocess the invalid records. Support
    for the prompt/cancel/stop when_invalid strategies has been dropped
- `rollback`, `errors` CLI stubs have been removed as they were never
    implemented
- `--edit` now no longer eats an argument when generating a migration
- Mutexes have been added to the registry to help with thread-safety. You will
    still need to make sure that your application is eager loaded on workers
- (breaking) The default write strategy has been changed to use replace bulk operations
    instead of a batch delete followed by a batch insert. You can swap back to
    delete then insert on a per-task basis, but you probably shouldn't
- An experimental option to wrap each document batch in a transaction has been
    added.
- (breaking) If a migration doesn't change a document, it will now skip writing
    it by default. To always write the document, call `always_write!`
- `batch_size` can now be configured per document task
- Rather than doing a single `pluck` on the `per_document` scope, the scope will
    now be iterated in subqueries of 100k IDs when retrieving IDs to queue jobs
    for.
- (breaking) `Hekenga::ParallelJob` takes different arguments now.
- (breaking) some internal methods have been renamed.
