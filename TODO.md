# TODO

## What Works

Everything below is implemented and tested (46 tests passing):

- **Primitives architecture**: ops.lua / validate.lua / core.lua
- **CLI flags**: --search, --show, --recent, --history, --sources, --note, --tag, --untag, --tagged, --recall, --orphans, --stats, --vacuum, --gc, --urgent, --clip, --git-log, --git-diff, --git-status, --daemon
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
- **Daemon mode**: `--daemon` (fork/setsid/PID file), `--daemon --foreground`, `--daemon --stop`, `--daemon --status`. Epoll-based event loop with timerfd for clipboard watch (2s) and vacuum (1h). Vendored deps: epoll, inotify, ljsocket, http server, websocket (from ~/git/lua/)

## Next: Daemon Extensions

Daemon core is implemented (epoll loop, timerfd, clipboard watch, vacuum, fork/PID). Remaining daemon tasks to add to the epoll set:

1. **inotify file watch** - Add inotify fd to epoll using vendored `dep/inotify.lua`. Wire `--watch`/`--unwatch`/`--watching` CLI flags. Store watch registrations in the database.

2. **Unix socket** - `$PAD_DIR/pad.sock` accepting newline-delimited JSON commands: `{"action": "ingest", "content": "...", "source": "..."}`. Use vendored `dep/ljsocket.lua`. Accept fd goes in epoll, each client connection added as a new fd.

3. **WebSocket listener** - HTTP server on localhost using vendored `dep/http/server.lua` + `dep/websocket.lua` on the daemon's epoll instance. Enables real-time IPC with browser extensions, VS Code extensions, Obsidian plugins, etc.

## Next: File Watcher Extension

Depends on daemon mode for continuous watching.

Prior art at `~/git/lua/dep/inotify.lua`: inotify wrapper that takes an `epoll` instance in its constructor and adds the inotify fd directly to the epoll set. Handles event parsing (variable-length `inotify_event` structs), per-watch callbacks, and watch removal. Full event mask enum included.

```lua
local inotify = require("dep.inotify")
local watcher = inotify.new(epoll)
local wd, remove = watcher:add("/path/to/file", inotify.event_mask.IN_MODIFY, function(event)
  -- ingest changed file
end)
```

This is the primary approach. For non-Linux platforms, fall back to timerfd + stat polling.

### CLI Integration

```
pad --watch /path/to/file     # register a path for watching (stored in annotations or a config table)
pad --unwatch /path/to/file   # stop watching
pad --watching                # list watched paths
```

Watch registrations stored as annotations on a sentinel object or in a simple config table in the database.

## Next: Web UI Extension (`pad --web`)

Local web UI served from extensions/web/. This is an extension, not core.

### HTTP Server

Prior art at `~/git/lua/lib/http/` — full HTTP/1.1 stack already built on the same epoll + ljsocket foundation:

- `lib/http/format.lua` — request/response parse and serialize (handles methods, headers, query params, URL decoding)
- `lib/http/server.lua` — HTTP server wrapping `lib/socket/server.lua`, takes an optional `epoll` instance
- `lib/websocket.lua` — WebSocket upgrade handler, integrates via `epoll:modify`

Vendor these into `dep/` alongside epoll.lua and ljsocket. The HTTP server shares the daemon's epoll instance — `--web` just adds a listener fd to the same loop. WebSocket support comes for free, enabling live-push to browser/extension clients.

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

1. HTTP server + WebSocket already vendored in `dep/` from daemon mode setup
2. Create `extensions/web/init.lua` — route handler calling `pad.core`, starts HTTP server on the daemon's epoll
3. Create `extensions/web/router.lua` mapping routes to handler functions
4. Create `extensions/web/static/index.html` with the frontend
5. Handlers call into `pad.core` for data (same API the CLI uses)
5. Wire `--web [port]` flag in pad.lua (default port 7778)

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
