# TODO

## Core

- **Dedup provenance gap** - when duplicate content arrives, we warm the object but don't record the new source event. The provenance of repeated captures is lost.

- **Batch coldness recalculation** - `recalculate_coldness()` function designed but not implemented. Would allow periodic maintenance to update all coldness values.

## Tests

- **Integration tests** - current tests only check hash and schema. Need tests that actually use sqlite (ingest, dedup, coldness warming, queries).

## Runtime Modes

- **Interactive (TTY)** - REPL + daemon
- **No TTY, no stdin** - daemon only
- **Piped stdin** - ingest and exit (current behavior)

## CLI

- `pad ls -la` - wrap shell commands, log as events with `source = "command"`
- `pad --recent` - show recent captures
- `pad --urgent` - time-aware priority (calendar integration)
- `pad --orphans` - show unlinked objects
- `pad --note` - note taking mode

## Web

- `pad --web` - local web UI for browsing/notes

## Query

- `pad --search <term>` - full-text search across objects
- `pad --show <hash>` - display object by hash prefix
- `pad --edges <hash>` - show what an object links to/from
- `pad --history` - timeline view of events
- `pad --sources` - list all sources that have contributed

## Annotations

- `pad --tag <hash> <tag>` - add annotation to object
- `pad --untag <hash> <tag>` - remove annotation
- `pad --tagged <tag>` - list objects with tag

## Maintenance

- Garbage collection for orphaned cold objects
- Compression for cold objects (zstd)
- Size budget enforcement (prune oldest cold objects when over limit)
- `pad --stats` - db size, object count, coldness distribution
- `pad --vacuum` - run maintenance tasks

## Sketching

- Detect shape: list, log, prose, code, structured
- Generate sketches on ingest (first N lines, summary)
- Store sketch as linked object with edge type `sketch_of`

## Shell Integration

- `pad <cmd>` - wrap any command, capture output, log as event
- zsh/bash preexec hook to auto-capture commands
- Fish shell integration
- `pad --recall <pattern>` - find past command outputs

## Edges

- `supersedes` - object replaces another
- `derived_from` - object was generated from another
- `references` - object mentions another
- `reply_to` - conversational threading

## Extensions

- clipboard
- browser
- git
- shell history
- email (mbox, notmuch)
- rss/atom feeds
- file watcher (inotify)
- screenshots (ocr → text object)
