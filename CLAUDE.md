# CLAUDE.md

Instructions for Claude Code in the pad repository.

## Overview

pad is a stdin sink that captures and structures text. Users pipe data into it, and it gets stored in a local SQLite database as linked objects.

```bash
echo "hello" | pad           # ingest from stdin
pad ls -la                   # shell wrapper (captures output)
pad --search "hello"         # search objects
pad --recent                 # recent captures
pad --show 5                 # display object by id or hash prefix
pad --note "remember this"   # quick note
```

## Code Style

Write readable, approachable, hackable code. New contributors should understand the codebase quickly. Keep the core small.

## Architecture

```
core/                    -- main library
  pad.lua               -- entry point, CLI flag dispatch
  pad/
    core.lua            -- composed operations (public API)
    ops.lua             -- atomic DB mutations (only code that writes)
    validate.lua        -- pure invariant enforcement (no side effects)
    schema.lua          -- database tables
    unwrap.lua          -- command prefix stripping (nix, sudo, time, etc.)
  dep/                  -- bundled dependencies (luajit, sqlite, xxhash, json)

extensions/             -- integrations with other tools
  parsers/              -- output format plugins (19 tools: rg, ls, grep, jq, tree, find, git, docker, curl, wget, make, cargo, npm, ps, top, df, du, sed, awk)
  shell/                -- bash/zsh integration
  clipboard/            -- clipboard capture (wl-paste, xclip, xsel, pbpaste)
  git/                  -- git log/diff/status capture
  browser/              -- (not yet implemented)
```

### Primitives Architecture

**All structural meaning is expressed as first-class PAD primitives (ops + validators), not ad-hoc Lua mutations.** Lua scripts may compose and sequence these primitives, but must not define invariants, schemas, or state structure themselves.

Three layers:

1. **ops.lua** - Atomic state mutations. Single SQL statements. No validation, no composition. The _only_ code that writes to the database.
2. **validate.lua** - Pure invariant enforcement. No side effects, no database access. These define what is structurally valid.
3. **core.lua** - Composed operations. Sequences ops + validators into the public API. This is what extensions and the CLI call.

When adding new functionality: define the op, define the validator (if needed), compose them in core. Never write SQL outside ops.lua.

### CLI Convention

- `pad --flag` = pad's own features (flags namespace)
- `pad <cmd> [args]` = shell wrapper (bare args = command to execute)

Everything pad does uses flags. Bare words are passed to shell. This means `pad ls` runs `ls` and captures its output, not a pad subcommand.

### Command Unwrapping

`unwrap.lua` recursively strips wrapper prefixes to find the real command:

```
pad time sudo nix run nixpkgs#ripgrep -- rg foo
     ^^^^                                         → wrapper: time
          ^^^^                                    → wrapper: sudo
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^        → wrapper: nix run
                                           ^^^^^^ → real command: rg foo
```

The event records `command = "rg foo"` with annotations `full_command` and `wrapper`. The base command (`rg`) is used for parser dispatch.

### Output Parsers

Extensions in `extensions/parsers/`. Each parser is a function `(output, args) → { shape, annotations }`. Parsers add structured metadata to objects (tool name, match counts, etc.) but never modify core behavior.

To add a new parser: create `extensions/parsers/foo.lua` returning a function, register it in `extensions/parsers/init.lua`.

## Data Model

Four tables:

- `events` - when/where/how something entered (provenance)
- `objects` - the actual content, content-addressed by hash
- `edges` - links between objects
- `annotations` - key/value metadata on events or objects

### Dedup Provenance

When duplicate content arrives, pad:
1. Warms the existing object (reduces coldness)
2. Creates a new event (so provenance is never lost)
3. Annotates the event with `dedup_object_id` pointing to the existing object

This means every source interaction is recorded, even for content we've seen before.

## Rules

These constraints prevent pad from becoming bloated:

1. **Capture is tiered** - Always store an event. Usually store a sketch (summary). Only store full content when needed or requested.

2. **Content is deduped** - Same bytes = same hash = stored once.

3. **Core detects shapes, not formats** - Core can say "this looks like a list" or "this looks like a log". Detailed format parsing belongs in extensions.

4. **Extensions add, never rewrite** - Extensions emit new objects and edges. They don't modify existing data.

5. **Everything has a source** - Every object must have provenance. Reject objects without it.

6. **Budgets live in core** - Core enforces limits on size, object count, etc. Extensions cannot bypass these.

7. **Things get cold** - Old unused objects have lower retrieval priority.

8. **Summarizing is normal** - The system can collapse, compress, and supersede objects as maintenance.

## Do Not

- Add UI, dashboards, or unnecessary complexity
- Let extensions bypass limits
- Store objects without provenance
- Store duplicate content
- Parse specific formats in core
- Write SQL outside ops.lua
- Define invariants outside validate.lua
- Use `--no-verify` on commits
