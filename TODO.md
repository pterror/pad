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

## Extensions

- clipboard
- browser
- git
- shell history
