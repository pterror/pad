# TODO

## What Works

Everything below is implemented and tested (41 tests passing):

- **Primitives architecture**: ops.lua / validate.lua / core.lua
- **CLI flags**: --search, --show, --recent, --history, --sources, --note, --tag, --untag, --tagged, --recall, --orphans, --stats, --vacuum, --gc, --urgent, --clip, --git-log, --git-diff, --git-status
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

## Next: Daemon Mode

When pad is run without TTY and without stdin, it should become a daemon. This is the biggest remaining architectural piece.

### Event Loop

Prior art at `~/git/lua/dep/epoll.lua`: ~200-line epoll wrapper with fd management, read/write/close callbacks, weak fds, and cross-platform support (wepoll.dll on Windows). Clean API:

- `epoll:add(fd, read_cb, close_cb, weak)` → returns `write`, `remove`
- `epoll:modify(fd, read_cb, close_cb)` → swap callbacks on existing fd
- `epoll:wait()` → single event dispatch (EPOLLIN, EPOLLOUT, EPOLLHUP, EPOLLRDHUP)
- `epoll:loop()` → `while count > 0 do wait() end`

This is the right approach. The daemon blocks on `epoll_wait` and wakes only when something happens — no busy-loop CPU burn, no sleep/poll cycles. On Linux, epoll handles everything pad needs: sockets, timerfd, inotify, signalfd. Windows support via wepoll (dlls at `~/git/lua/dep/wepoll*`).

Timers use `timerfd_create` via FFI — each timer is just another fd in the epoll set:

```lua
ffi.cdef[[
  int timerfd_create(int clockid, int flags);
  int timerfd_settime(int fd, int flags, const struct itimerspec *new, struct itimerspec *old);
]]
```

Prior art at `~/git/lua/lib/websocket.lua`: RFC 6455 websocket implementation that integrates directly with the epoll module (takes an `epoll` instance, uses `epoll:modify`). Handles upgrade handshake, frame encode/decode, masking, continuation frames, ping/pong, close. This enables WebSocket IPC with browser extensions, VS Code extensions, Obsidian plugins, etc.

### Daemon Lifecycle

```
pad --daemon              # start daemon (fork to background)
pad --daemon --foreground # run in foreground (for debugging/systemd)
pad --daemon --stop       # stop running daemon
pad --daemon --status     # check if daemon is running
```

PID file at `$PAD_DIR/pad.pid`. Daemon writes log to `$PAD_DIR/pad.log`.

### Daemon Tasks

The daemon's epoll set contains these fds:

1. **Clipboard timerfd** (every 2s) - Read clipboard via extensions/clipboard, compare hash to last seen. If different, ingest with `source = "clipboard"`. Dedup handles repeated copies.

2. **File watch** (inotify fd, or timerfd fallback every 5s) - Watch registered paths for changes. Ingest changed files with `source = "file:watch"`. Watch paths configured via `pad --watch /path/to/file`. inotify fds slot directly into epoll.

3. **Vacuum timerfd** (every 1h) - Run `pad.recalculate_coldness()`.

4. **Unix socket** - `$PAD_DIR/pad.sock` accepting newline-delimited JSON commands: `{"action": "ingest", "content": "...", "source": "..."}`. Lets other tools feed into pad without spawning a process. Accept fd goes in epoll, each client connection added as a new fd.

5. **WebSocket listener** (optional) - HTTP server on localhost that upgrades to WebSocket using `~/git/lua/lib/websocket.lua`. Enables real-time IPC with browser extensions, VS Code extensions, Obsidian plugins, etc. Same epoll instance — the websocket module already integrates via `epoll:modify`.

### Vendoring

Copy from `~/git/lua/` into pad's `dep/`:

```
dep/epoll.lua              ← dep/epoll.lua
dep/inotify.lua            ← dep/inotify.lua       (file watcher, epoll-native)
dep/ljsocket.lua           ← dep/ljsocket.lua
dep/sha1.lua               ← dep/sha1.lua          (websocket needs it)
dep/base64.lua             ← dep/base64.lua         (websocket needs it)
dep/wepoll.dll             ← dep/wepoll.dll         (Windows epoll shim)
dep/wepoll32.dll           ← dep/wepoll32.dll       (Windows 32-bit)
dep/http/format.lua        ← lib/http/format.lua   (request/response parse)
dep/http/server.lua        ← lib/http/server.lua   (HTTP server)
dep/http/status.lua        ← lib/http/status.lua   (status code names)
dep/socket/server.lua      ← lib/socket/server.lua (TCP server)
dep/websocket.lua          ← lib/websocket.lua     (WebSocket upgrade)
dep/urlencode.lua          ← lib/urlencode.lua     (URL decoding)
dep/utf8.lua               ← lib/utf8.lua          (websocket UTF-8 validation)
```

Require paths need adjusting after copy (e.g. `require("lib.http.format")` → `require("dep.http.format")`).

### Implementation Plan

1. Vendor the above files, fix require paths
2. Add `ops.lua`: daemon PID file ops (write_pid, read_pid, clear_pid)
3. Add `core/pad/daemon.lua`: daemon lifecycle (start, stop, status, main loop with epoll)
4. Wire into pad.lua: `--daemon` flag dispatch
5. Clipboard watch: timerfd in epoll, use existing extensions/clipboard/init.lua, `last_hash` state
6. File watch: inotify fd in epoll (fall back to timerfd + stat polling)
7. Unix socket: ljsocket bind + epoll:add for accept, each client fd added to epoll
8. WebSocket listener: http/server.lua + websocket.lua on the daemon's epoll instance

### Daemonization in LuaJIT

```lua
local ffi = require("ffi")
ffi.cdef[[
  int fork(void);
  int setsid(void);
  int close(int fd);
  int getpid(void);
]]

local pid = ffi.C.fork()
if pid > 0 then os.exit(0) end  -- parent exits
if pid < 0 then error("fork failed") end
ffi.C.setsid()                   -- new session
-- redirect stdout/stderr to log file
-- write PID file
-- enter main loop
```

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
