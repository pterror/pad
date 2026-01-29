# CLI Reference

## Usage

```bash
... | pad                  # ingest from stdin
pad <cmd> [args...]        # shell wrapper (captures output)
pad --flag [args...]       # pad's own features
```

`pad --flag` = pad features. Bare words = shell wrapper.

## Flags

### Querying

| Flag | Description |
|------|-------------|
| `--search "term"` | Search objects by content |
| `--show <id\|hash>` | Display object by ID or hash prefix |
| `--recent` | Recent captures |
| `--history` | Event timeline |
| `--sources` | List all sources |
| `--recall <pattern>` | Search past commands |
| `--orphans` | Unlinked objects |
| `--stats` | Database statistics |
| `--urgent` | Unreviewed and action items |
| `--tagged <tag>` | List objects with tag |

### Writing

| Flag | Description |
|------|-------------|
| `--note "text"` | Quick note |
| `--tag <id>:<tag>` | Tag an object |
| `--untag <id>:<tag>` | Remove tag |
| `--clip` | Capture clipboard |

### Git

| Flag | Description |
|------|-------------|
| `--git-log [n]` | Capture recent git commits |
| `--git-diff [ref]` | Capture git diff |
| `--git-status` | Capture git status |

### File Watching

| Flag | Description |
|------|-------------|
| `--watch <path>` | Add file watch |
| `--unwatch <path>` | Remove file watch |
| `--watching` | List file watches |

### Daemon

| Flag | Description |
|------|-------------|
| `--daemon` | Start background daemon |
| `--daemon --foreground` | Run daemon in foreground |
| `--daemon --stop` | Stop daemon |
| `--daemon --status` | Check daemon status |

### Maintenance

| Flag | Description |
|------|-------------|
| `--vacuum` | Recalculate coldness |
| `--gc` | Show GC candidates |
| `--gc --confirm` | Delete cold orphans |

## Shell Wrapper

```bash
pad ls -la          # runs ls -la and captures output
pad rg foo          # runs rg foo, parses output with rg parser
pad time sudo rg x  # unwraps time/sudo, records command as "rg x"
```

Wrapper prefixes (nix, sudo, time, env, etc.) are stripped to find the real command. The base command is used for parser dispatch.
