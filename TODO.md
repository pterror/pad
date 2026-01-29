# TODO

## Core

- ~~**Dedup provenance gap**~~ - DONE. Duplicate ingest now records a new event with `dedup_object_id` annotation.

- ~~**Batch coldness recalculation**~~ - DONE. `pad --vacuum` runs age-based cooling (0.01/day).

## Tests

- ~~**Integration tests**~~ - DONE. 33 tests: hash, schema, validators, integration (ingest, dedup, warmth, linking, annotations, shape detection, provenance).

## Runtime Modes

- **Interactive (TTY)** - REPL + daemon (stub exists)
- **No TTY, no stdin** - daemon only (stub exists)
- ~~**Piped stdin**~~ - DONE. `echo "hello" | pad`

## CLI

- ~~`pad ls -la`~~ - DONE. Shell wrapper with `source = "command"`
- ~~`pad --recent`~~ - DONE
- `pad --urgent` - time-aware priority (calendar integration)
- ~~`pad --orphans`~~ - DONE
- ~~`pad --note`~~ - DONE. `pad --note "text"` or `pad --note` for stdin

## Web

- `pad --web` - local web UI for browsing/notes

## Query

- ~~`pad --search <term>`~~ - DONE
- ~~`pad --show <id|hash>`~~ - DONE. Supports id or hash prefix
- `pad --edges <id|hash>` - show what an object links to/from (edges shown in --show)
- ~~`pad --history`~~ - DONE. Event timeline with object counts
- ~~`pad --sources`~~ - DONE. Source breakdown with event counts

## Annotations

- ~~`pad --tag <id>:<tag>`~~ - DONE
- ~~`pad --untag <id>:<tag>`~~ - DONE
- ~~`pad --tagged <tag>`~~ - DONE

## Maintenance

- Garbage collection for orphaned cold objects
- Compression for cold objects (zstd)
- Size budget enforcement (prune oldest cold objects when over limit)
- ~~`pad --stats`~~ - DONE
- ~~`pad --vacuum`~~ - DONE. Runs coldness recalculation

## Sketching

- Detect shape: list, log, prose, code, structured (basic shapes done)
- Generate sketches on ingest (first N lines, summary) - DONE
- Store sketch as linked object with edge type `sketch_of`

## Shell Integration

- ~~`pad <cmd>`~~ - DONE. Shell wrapper with `source = "command"`
- ~~zsh/bash preexec hook to auto-capture commands~~ - DONE. `pad-preexec` in pad.bash
- Fish shell integration
- ~~`pad --recall <pattern>`~~ - DONE. Search past command outputs

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
- screenshots (ocr -> text object)
