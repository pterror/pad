# TODO

## What Works

Everything below is implemented and tested (58 tests passing):

- **Primitives architecture**: ops.lua / validate.lua / core.lua
- **CLI flags**: --search, --show, --recent, --history, --sources, --note, --tag, --untag, --tagged, --recall, --orphans, --stats, --vacuum, --gc, --urgent, --clip, --git-log, --git-diff, --git-status, --watch, --unwatch, --watching, --daemon
- **Interactive REPL**: TTY + no args starts REPL with /command dispatch, bare text captured as notes
- **Shell wrapper**: `pad <cmd>` captures output with `source = "command"`
- **Command unwrapping**: nix run/shell/develop, sudo, time, strace, ltrace, env, nice, timeout, watch
- **Output parsers**: rg, ls, grep, jq, tree, find, git, docker, curl, wget, make, cargo, npm, ps, top, df, du, sed, awk (plugin registry in extensions/parsers/)
- **Dedup provenance**: duplicate ingest records new event + annotation
- **Coldness**: warming on access/dedup, age-based cooling via --vacuum
- **Garbage collection**: `--gc` shows cold orphans (coldness >= 0.9, no edges, no annotations), `--gc --confirm` deletes them
- **Budget enforcement**: validate.budget_objects and validate.budget_edges enforced in core.link
- **Edge type validation**: validate.relation() enforces known types (supersedes, derived_from, references, reply_to, sketch_of)
- **Sketch-as-object**: core.create_sketch/get_sketches creates linked sketch objects with sketch_of edges (inline sketch kept for quick display)
- **Time awareness**: `--urgent` surfaces unreviewed objects (access_count <= 1) and objects tagged todo/urgent/deadline
- **Clipboard extension**: `--clip` captures clipboard (auto-detects wl-paste, xclip, xsel, pbpaste)
- **Git extension**: `--git-log [n]`, `--git-diff [ref]`, `--git-status` capture git output with source = "git:*"
- **Shell integration**: pad.bash with aliases and zsh preexec hook
- **Daemon mode**: `--daemon` (fork/setsid/PID file), `--daemon --foreground`, `--daemon --stop`, `--daemon --status`. Epoll-based event loop with timerfd for clipboard watch (2s) and vacuum (1h)
- **Inotify file watch**: `--watch <path>`, `--unwatch <path>`, `--watching`. Watches stored in `watches` table. Daemon registers IN_MODIFY|IN_CLOSE_WRITE callbacks that ingest file content with `source = "watch"`
- **Unix socket IPC**: `$PAD_DIR/pad.sock` accepting newline-delimited JSON commands via shared dispatch module. Actions: ingest, search, recent, show, stats, note, tag, untag
- **HTTP/WebSocket listener**: Port 7778. HTTP serves JSON stats on `/` and `/status`. WebSocket upgrade uses same dispatch protocol as unix socket. Enables real-time IPC with browser extensions, VS Code extensions, Obsidian plugins, etc.
- **Dispatch module**: `pad/dispatch.lua` — shared JSON action routing used by both unix socket and WebSocket, with pcall error handling

## Next: Web UI Extension (`pad --web`)

Local web UI served from extensions/web/. This is an extension, not core.

The HTTP server and WebSocket are already running on port 7778 as part of the daemon. The web UI would add:

### API Endpoints

```
GET  /api/objects              # list objects (query params: ?search=, ?shape=, ?limit=)
GET  /api/objects/:id          # get single object with annotations/edges
GET  /api/events               # event timeline
GET  /api/stats                # database stats
GET  /api/urgent               # urgent items
POST /api/ingest               # ingest content (body = content, headers for source/metadata)
POST /api/objects/:id/tag      # add tag
POST /api/objects/:id/note     # create linked note
```

### Frontend

Static HTML + vanilla JS (no build step, no framework). Served from `extensions/web/static/`.

Pages:
- **Dashboard**: recent objects, urgent items, stats
- **Search**: full-text search with results
- **Object detail**: show object with annotations, edges, linked sketches
- **Note input**: text area that POSTs to /api/ingest with source = "web"

The frontend should be a single HTML file with embedded CSS/JS for simplicity. No npm, no bundler.

### Implementation Plan

1. Extend daemon's HTTP handler with path-based routing for `/api/*` endpoints
2. Create `extensions/web/init.lua` — route handler calling `pad.core`
3. Create `extensions/web/static/index.html` with the frontend
4. Handlers call into `pad.core` for data (same API the CLI uses)

## Low Priority / Future

- Fish shell integration
- Email extension (mbox, notmuch)
- RSS/Atom feed extension
- Screenshot OCR extension
- Export/import (pad dump, pad load)
- Full-text search index (SQLite FTS5)
- Compression for cold objects (zstd via FFI)
- REPL readline/linenoise support for history and editing
- Exit code tracking for shell wrapper commands (for --urgent)
- Events during unusual hours detection (for --urgent)
- Non-Linux fallback for inotify (timerfd + stat polling)
