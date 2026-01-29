# TODO

## What Works

Everything below is implemented and tested (33 tests passing):

- **Primitives architecture**: ops.lua / validate.lua / core.lua
- **CLI flags**: --search, --show, --recent, --history, --sources, --note, --tag, --untag, --tagged, --recall, --orphans, --stats, --vacuum
- **Shell wrapper**: `pad <cmd>` captures output with `source = "command"`
- **Command unwrapping**: nix run/shell/develop, sudo, time, strace, ltrace, env, nice, timeout, watch
- **Output parsers**: rg, ls, grep, jq, tree (plugin registry in extensions/parsers/)
- **Dedup provenance**: duplicate ingest records new event + annotation
- **Coldness**: warming on access/dedup, age-based cooling via --vacuum
- **Shell integration**: pad.bash with aliases and zsh preexec hook

## Next: High Priority

### Interactive REPL

When pad is run with a TTY and no args, it should start a REPL. The stub exists in pad.lua (line ~323). The REPL should support:
- All flag operations as commands (search, show, recent, tag, etc.)
- Note taking as the default action (type text, hit enter, it's captured)
- Possibly readline/linenoise for history and editing

Decision needed: should the REPL be in core or an extension?

### Daemon Mode

When pad is run without TTY and without stdin, it should become a daemon that:
- Watches clipboard for changes (clipboard extension)
- Monitors file changes (inotify extension)
- Runs periodic vacuum (coldness recalculation)
- Listens on a socket for programmatic ingest?

This is the "always-on pad" mode. Needs design thought.

### Web UI (`pad --web`)

Local web UI for browsing, searching, and note-taking. Notes should be "implicit in the UI" per original spec. Consider:
- Lightweight HTTP server in LuaJIT (via FFI to something, or pure Lua)
- Static HTML + JS served from extensions/web/
- REST-ish API: GET /objects, GET /objects/:id, POST /ingest, etc.
- The web UI is an extension, not core

### Calendar/Time Awareness (`pad --urgent`)

Objects and events have timestamps. `--urgent` should surface things that are time-sensitive:
- Recently ingested but not yet reviewed
- Objects with "deadline" or "todo" annotations
- Commands that failed (exit code tracking?)
- Events that happened during unusual hours

Needs design: how does pad know something is urgent?

## Next: More Parsers

Add parsers for commonly piped tools. Each is a file in `extensions/parsers/`:

- **find** - file counts, directory pattern
- **sed/awk** - transformation metadata
- **git** - git log, git diff, git status output
- **docker** - container/image listings
- **curl/wget** - HTTP status, headers, URL
- **make/cargo/npm** - build output, error counts
- **ps/top** - process listings
- **df/du** - disk usage

Pattern: create `extensions/parsers/foo.lua` returning `function(output, args) -> { shape, annotations }`, register in `init.lua`.

## Next: Extensions

### Clipboard (`extensions/clipboard/`)

- Watch clipboard for changes (platform-specific: xclip, pbpaste, wl-paste)
- Ingest clipboard content with `source = "clipboard"`
- Dedup handles repeated copies gracefully

### Git (`extensions/git/`)

- `pad --git-log` or auto-capture on commit
- Ingest commit messages, diffs with `source = "git:commit"`
- Link related commits via edges

### File Watcher (`extensions/watch/`)

- inotify-based file monitoring
- Ingest file contents on change with `source = "file:watch"`
- Useful for daemon mode

## Next: Core Improvements

### Garbage Collection

Cold orphaned objects should eventually be pruned. Design:
1. `--vacuum` already recalculates coldness
2. Add a GC step: objects with coldness > 0.9 AND no edges AND no annotations → candidate for deletion
3. Maybe a `--gc` flag that shows candidates, `--gc --confirm` to actually delete
4. Need `ops.delete_object` in ops.lua

### Sketch-as-Object

Currently sketches are stored inline on the object row. The CLAUDE.md rule says "summarizing is normal" and the TODO originally proposed storing sketches as linked objects with `edge_type = "sketch_of"`. This would allow:
- Multiple sketches per object (different granularities)
- Sketches that supersede each other
- Extensions generating richer summaries

### Budget Enforcement

`budgets.max_objects_per_event` and `max_edges_per_event` are defined but not enforced. Add validators.

### Edge Types

The schema supports arbitrary relation strings. Codify the standard set:
- `supersedes` - object replaces another
- `derived_from` - object was generated from another
- `references` - object mentions another
- `reply_to` - conversational threading
- `sketch_of` - sketch/summary relationship

Consider adding `validate.relation()` to enforce known types, or keep it open.

## Low Priority / Future

- Fish shell integration
- Email extension (mbox, notmuch)
- RSS/Atom feed extension
- Screenshot OCR extension
- Export/import (pad dump, pad load)
- Full-text search index (SQLite FTS5)
- Compression for cold objects (zstd via FFI)
