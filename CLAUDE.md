# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hekenga is a Ruby gem providing a migration framework for MongoDB (via Mongoid). It supports sequential and parallel document processing via ActiveJob, with error recovery, validation tracking, and a Thor-based CLI.

## Common Commands

```bash
# Run full test suite (requires MongoDB - see docker-compose.yml)
rake spec

# Run a single spec file
rake spec SPEC=spec/hekenga/document_task_spec.rb

# Install gem locally
bundle exec rake install

# Interactive console with gem loaded
bin/console
```

## Architecture

### Migration Flow

```
Migration.perform! → MasterProcess.run! → launches tasks in threads
  SimpleTask:   executes up/down blocks directly
  DocumentTask: iterates documents → batch → execute → write (sequential)
  ParallelTask: splits into ID batches → enqueues ParallelJob per batch (via ActiveJob)
```

### Key Components

- **`Hekenga::Migration`** — main migration class, orchestrates tasks
- **`Hekenga::MasterProcess`** — launches tasks, manages execution/recovery/progress
- **`Hekenga::DSL::*`** — fluent DSL for defining migrations (`DSL::Migration`, `DSL::SimpleTask`, `DSL::DocumentTask`)
- **`Hekenga::DocumentTaskExecutor`** — core document processing: filter → up block → validate → write
- **`Hekenga::ParallelTask`** / **`Hekenga::ParallelJob`** — parallel execution via ActiveJob
- **`Hekenga::DocumentTaskRecord`** — Mongoid doc tracking parallel task progress
- **`Hekenga::Log`** — Mongoid doc tracking migration/task status (`:naught`, `:running`, `:complete`, `:failed`, `:skipped`)
- **`Hekenga::Failure::*`** — error/validation/write/cancelled failure tracking subclasses
- **`Hekenga::IdIterator`** / **`Hekenga::MongoidIterator`** — efficient document iteration for parallel vs sequential paths

### Task Types

- **SimpleTask** — one-off up/down blocks, no document iteration
- **DocumentTask** — per-document processing with scope, filter, setup, up, down, after blocks; supports `parallel!`, `timeless!`, `always_write!`, `use_transaction!`, configurable write strategies (`:update` vs `:delete_then_insert`)

### Configuration

Via `Hekenga.configure` block — sets migration directory and report frequency. Thread-safe registry tracks all migrations.

## Dependencies

- **mongoid** (>= 6), **activejob** (>= 5), **thor** (1.2.1)
- Test: **rspec** (~> 3.0), **database_cleaner-mongoid** (~> 2.0), **pry**
