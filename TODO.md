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

LuaJIT has no built-in event loop. Options:

1. **luv (libuv bindings)** - Mature, well-tested. Provides timers, file watchers, TCP/UDP, signals. Available via luarocks. This is the most practical choice. The FFI overhead is minimal.

2. **epoll via FFI** - Roll our own with `ffi.cdef` for epoll_create, epoll_ctl, epoll_wait. Minimal dependencies but significant work: need to handle fd management, timers, signal handling manually. Only works on Linux.

3. **select() via FFI** - Simpler than epoll, cross-platform, but limited to 1024 fds and no inotify integration.

4. **Busy loop with sleep** - Simplest: `while true do check_clipboard(); check_files(); vacuum(); ffi.C.sleep(interval) end`. No real concurrency but might be enough for pad's use case. Clipboard polling every 2s, file stat checks, periodic vacuum.

Recommendation: start with option 4 (busy loop). It's simple, has no dependencies, and pad's daemon workload is light. If it proves insufficient, migrate to luv.

### Daemon Lifecycle

```
pad --daemon              # start daemon (fork to background)
pad --daemon --foreground # run in foreground (for debugging/systemd)
pad --daemon --stop       # stop running daemon
pad --daemon --status     # check if daemon is running
```

PID file at `$PAD_DIR/pad.pid`. Daemon writes log to `$PAD_DIR/pad.log`.

### Daemon Tasks

The daemon runs a loop with these periodic tasks:

1. **Clipboard watch** (every 2s) - Read clipboard via extensions/clipboard, compare hash to last seen. If different, ingest with `source = "clipboard"`. Dedup handles repeated copies.

2. **File watch** (every 5s or inotify) - Check registered watch paths for changes. Ingest changed files with `source = "file:watch"`. Watch paths configured via `pad --watch /path/to/file`.

3. **Vacuum** (every 1h) - Run `pad.recalculate_coldness()`.

4. **Socket listener** (optional) - Unix socket at `$PAD_DIR/pad.sock` accepting newline-delimited JSON commands: `{"action": "ingest", "content": "...", "source": "..."}`. This lets other tools feed into pad programmatically without spawning a process.

### Implementation Plan

1. Add `ops.lua`: daemon PID file ops (write_pid, read_pid, clear_pid)
2. Add `core/pad/daemon.lua`: daemon lifecycle (start, stop, status, main loop)
3. Wire into pad.lua: `--daemon` flag dispatch
4. Clipboard watch: use existing extensions/clipboard/init.lua, add `last_hash` state
5. File watch: new `extensions/watch/init.lua` using `os.execute("stat ...")` for polling, or inotify FFI for event-driven
6. Socket: `ffi.cdef` for socket/bind/listen/accept/read, or skip for v1

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

Depends on daemon mode for continuous watching. Two approaches:

### Polling (no dependencies)

```lua
-- extensions/watch/init.lua
local mod = {}
local watched = {}  -- path -> { mtime, size }

function mod.add(path)
  local attr = lfs.attributes(path) -- or os.execute("stat ...")
  watched[path] = { mtime = attr.modification, size = attr.size }
end

function mod.check()
  local changed = {}
  for path, prev in pairs(watched) do
    local attr = lfs.attributes(path)
    if attr and (attr.modification ~= prev.mtime or attr.size ~= prev.size) then
      changed[#changed + 1] = path
      prev.mtime = attr.modification
      prev.size = attr.size
    end
  end
  return changed
end
```

### inotify via FFI (Linux only, event-driven)

```lua
ffi.cdef[[
  int inotify_init(void);
  int inotify_add_watch(int fd, const char *pathname, uint32_t mask);
  int inotify_rm_watch(int fd, int wd);
  typedef struct { int wd; uint32_t mask; uint32_t cookie; uint32_t len; char name[]; } inotify_event;
]]

local IN_MODIFY = 0x00000002
local IN_CREATE = 0x00000100
local IN_DELETE = 0x00000200

local fd = ffi.C.inotify_init()
local wd = ffi.C.inotify_add_watch(fd, "/path/to/watch", bit.bor(IN_MODIFY, IN_CREATE))
-- read events from fd in the daemon loop
```

Recommendation: start with polling. It works everywhere, is simpler, and pad's file watch use case (monitoring a handful of files) doesn't need inotify's efficiency.

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

LuaJIT options for HTTP serving:

1. **Pure Lua HTTP** - Parse HTTP/1.1 requests manually over TCP sockets. LuaJIT's FFI makes raw sockets straightforward. A minimal server is ~150 lines: socket(), bind(), listen(), accept(), read request line + headers, route, write response. No dependencies.

2. **luv + http-parser** - If we adopt luv for daemon mode, use its TCP server with a lightweight HTTP parser.

3. **Embed a C server via FFI** - Link against mongoose or microhttpd. Heavier dependency but battle-tested HTTP handling.

Recommendation: pure Lua HTTP via FFI sockets. Pad only serves localhost, handles low traffic, and doesn't need HTTPS or HTTP/2. A minimal implementation is sufficient and keeps dependencies at zero.

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

1. Create `extensions/web/init.lua` with minimal HTTP server (FFI sockets)
2. Create `extensions/web/router.lua` mapping routes to handler functions
3. Create `extensions/web/static/index.html` with the frontend
4. Handlers call into `pad.core` for data (same API the CLI uses)
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
