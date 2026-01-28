# CLAUDE.md

Instructions for Claude Code in the pad repository.

## Overview

pad is a stdin sink that captures and structures text. Users pipe data into it, and it gets stored in a local SQLite database as linked objects.

```bash
echo "hello" | pad
ls -la | pad
pad query "hello"
```

## Code Style

Write readable, approachable, hackable code. New contributors should understand the codebase quickly. Keep the core small.

## Architecture

```
core/                    -- main library
  pad.lua               -- entry point
  pad/
    core.lua            -- data model, limits
    schema.lua          -- database tables
  dep/                  -- bundled dependencies (luajit, sqlite)

extensions/             -- integrations with other tools
  clipboard/
  shell/
  browser/
  ...
```

Extensions are separate packages that call into core. Each extension passes a `source` parameter so pad knows where data came from:

```lua
pad.ingest(content, { source = "clipboard" })
pad.ingest(content, { source = "browser", url = "..." })
pad.ingest(content, { source = "git:commit", hash = "..." })
```

## Data Model

Four tables:

- `events` - when/where/how something entered (provenance)
- `objects` - the actual content, content-addressed by hash
- `edges` - links between objects
- `annotations` - key/value metadata on events or objects

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
- Use `--no-verify` on commits
