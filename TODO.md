# TODO

## What Works

Everything below is implemented and tested (91 tests passing):

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
- **Shell integration**: pad.bash (bash/zsh) and pad.fish (fish) with aliases, completions, and preexec hooks
- **Daemon mode**: `--daemon` (fork/setsid/PID file), `--daemon --foreground`, `--daemon --stop`, `--daemon --status`. Epoll-based event loop with timerfd for clipboard watch (2s) and vacuum (1h)
- **Inotify file watch**: `--watch <path>`, `--unwatch <path>`, `--watching`. Watches stored in `watches` table. Daemon registers IN_MODIFY|IN_CLOSE_WRITE callbacks that ingest file content with `source = "watch"`
- **Unix socket IPC**: `$PAD_DIR/pad.sock` accepting newline-delimited JSON commands via shared dispatch module. Actions: ingest, search, recent, show, stats, note, tag, untag
- **HTTP/WebSocket listener**: Port 7778. HTTP serves JSON stats on `/` and `/status`. WebSocket upgrade uses same dispatch protocol as unix socket. Enables real-time IPC with browser extensions, VS Code extensions, Obsidian plugins, etc.
- **Dispatch module**: `pad/dispatch.lua` — shared JSON action routing used by both unix socket and WebSocket, with pcall error handling
- **Web UI extension**: `extensions/web/` — local web UI on daemon port 7778. Table router with chain composition, JSON API endpoints, single-file HTML frontend (dark terminal theme, vanilla JS, no build step). See `docs/api.md` for endpoint reference
- **FTS5 full-text search**: `--search` uses SQLite FTS5 with BM25 ranking. Supports phrases ("hello world"), boolean (test AND another), and prefix (hel*) queries. Auto-migrates existing databases
- **Browser extension**: `extensions/browser/` — Chrome (MV3) and Firefox (MV2) context menu capture via WebSocket
- **Export/import**: `--dump [file]` exports all data to JSON, `--load <file>` imports from dump (rebuilds FTS index)

## Next Up

### Browser Extension Enhancements

Basic extension done (`extensions/browser/`). Potential additions:

- ~~Keyboard shortcuts (Ctrl+Shift+P to capture page)~~ DONE
- ~~Badge notification on successful capture~~ DONE
- ~~Options page to configure daemon URL/port~~ DONE
- ~~Capture page as markdown (readability-style extraction)~~ DONE
- ~~Capture all links on page (batch)~~ DONE
- ~~Capture visible screenshot~~ DONE (as data URL)
- ~~Capture code blocks from pages (detect `<pre>`, `<code>`)~~ DONE
- ~~Capture tables as structured data~~ DONE (TSV format)

### Other

## Low Priority / Future

- ~~Fish shell integration~~ DONE
- Email extension (mbox, notmuch)
- RSS/Atom feed extension
- Screenshot OCR extension
- ~~Export/import (pad dump, pad load)~~ DONE
- ~~Full-text search index (SQLite FTS5)~~ DONE - auto-migrates existing DBs
- Compression for cold objects (zstd via FFI)
- REPL readline/linenoise support for history and editing
- Exit code tracking for shell wrapper commands (for --urgent)
- Events during unusual hours detection (for --urgent)
- Non-Linux fallback for inotify (timerfd + stat polling)
