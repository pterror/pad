# Architecture

## Layout

```
core/                    -- main library
  pad.lua               -- entry point, CLI flag dispatch
  pad/
    core.lua            -- composed operations (public API)
    ops.lua             -- atomic DB mutations (only code that writes)
    validate.lua        -- pure invariant enforcement (no side effects)
    schema.lua          -- database tables
    dispatch.lua        -- shared JSON action dispatch for IPC
    daemon.lua          -- epoll event loop
    unwrap.lua          -- command prefix stripping
  dep/                  -- bundled dependencies

extensions/             -- integrations
  parsers/              -- output format plugins (19 tools)
  clipboard/            -- clipboard capture
  git/                  -- git log/diff/status capture
  web/                  -- web UI and HTTP API
  shell/                -- bash/zsh integration
```

## Three-Layer Primitives

All structural meaning is expressed as first-class primitives:

1. **ops.lua** — Atomic state mutations. Single SQL statements. No validation, no composition. The only code that writes to the database.
2. **validate.lua** — Pure invariant enforcement. No side effects, no database access.
3. **core.lua** — Composed operations. Sequences ops + validators into the public API.

When adding functionality: define the op, define the validator (if needed), compose in core.

## Data Model

Four tables:

- **events** — when/where/how something entered (provenance)
- **objects** — content, content-addressed by hash
- **edges** — links between objects (supersedes, derived_from, references, reply_to, sketch_of)
- **annotations** — key/value metadata on events or objects

### Dedup

Same content → same hash → stored once. Duplicate ingest warms the existing object and creates a new event annotated with `dedup_object_id`.

### Tiering

Objects are tiered by size:

| Size | Tier | Storage |
|------|------|---------|
| ≤ 4 KB | full | sketch + payload |
| 4 KB – 1 MB | sketch | sketch only |
| > 1 MB | sketch | sketch only (with warning) |

### Coldness

Objects start hot (coldness = 0). Coldness increases over time based on last access. Accessing or deduping warms an object. `--gc` targets cold orphans (coldness ≥ 0.9, no edges, no annotations).

## Daemon

Epoll-based event loop with:

- **Clipboard timer** (2s) — polls clipboard for changes
- **Vacuum timer** (1h) — recalculates coldness
- **Inotify** — watches registered files for changes
- **Unix socket** — `$PAD_DIR/pad.sock` for JSON IPC
- **HTTP/WebSocket** — port 7778 for web UI and API

## Extensions

Extensions add, never rewrite. They emit new objects and edges but don't modify existing data. Core enforces budgets that extensions cannot bypass.
