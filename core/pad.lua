#!/usr/bin/env luajit
--[[
pad - cognitive stdin sink

usage:
  ... | pad                  # ingest from stdin
  pad <cmd> [args...]        # shell wrapper (captures output)
  pad --search "..."         # search objects
  pad --recent               # recent captures
  pad --show <id|hash>       # display object
  pad --history              # event timeline
  pad --sources              # list all sources
  pad --note "..."           # quick note
  pad --tag <id>:<tag>       # tag an object
  pad --untag <id>:<tag>     # remove tag
  pad --tagged <tag>         # list tagged objects
  pad --recall <pattern>     # search past commands
  pad --orphans              # unlinked objects
  pad --stats                # database stats
  pad --vacuum               # maintenance
  pad --gc                   # show GC candidates
  pad --gc --confirm         # delete cold orphans
  pad --urgent               # surface unreviewed/action items
  pad --clip                 # capture clipboard
  pad --git-log [n]          # capture recent git commits
  pad --git-diff [ref]       # capture git diff
  pad --git-status           # capture git status
  pad --watch <path>         # add file watch
  pad --unwatch <path>       # remove file watch
  pad --watching             # list file watches
  pad --daemon               # start background daemon
  pad --daemon --foreground  # run daemon in foreground
  pad --daemon --stop        # stop daemon
  pad --daemon --status      # check daemon status
]]

package.path = package.path .. ";./?.lua;./?/init.lua"
package.path = package.path .. ";../extensions/?.lua;../extensions/?/init.lua"

local pad = require("pad.core")
local unwrap = require("pad.unwrap")
local daemon = require("pad.daemon")
local ok_parsers, parsers = pcall(require, "parsers")
if not ok_parsers then parsers = nil end
local ok_clip, clipboard = pcall(require, "clipboard")
if not ok_clip then clipboard = nil end
local ok_git, git_ext = pcall(require, "git")
if not ok_git then git_ext = nil end

local function is_tty()
  local _, code = os.execute("test -t 0")
  return code == 0
end

local function parse_args(args)
  local flags = {}
  local cmd_args = {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if a:match("^%-%-") then
      local key = a:sub(3)
      if args[i + 1] and not args[i + 1]:match("^%-%-") then
        flags[key] = args[i + 1]
        i = i + 2
      else
        flags[key] = true
        i = i + 1
      end
    else
      for j = i, #args do
        cmd_args[#cmd_args + 1] = args[j]
      end
      break
    end
  end
  return flags, cmd_args
end

-- resolve id or hash prefix to object id
local function resolve_id(id_or_hash)
  local id = tonumber(id_or_hash)
  if id then return id end
  return pad.find_by_hash_prefix(id_or_hash)
end

-- flag handlers

local function do_search(term)
  -- Use FTS5 for full-text search with BM25 ranking
  local results = pad.search(term)
  local count = 0
  for id, shape, sketch in results do
    print(string.format("[%d] (%s) %s", id, shape, sketch:sub(1, 80)))
    count = count + 1
  end
  if count == 0 then
    print("no results")
  end
end

local function do_recent()
  local results = pad.query([[
    SELECT o.id, o.shape, o.sketch, e.source, e.created_at
    FROM objects o
    JOIN events e ON e.id = o.event_id
    ORDER BY e.created_at DESC
    LIMIT 20;
  ]])
  for id, shape, sketch, source, created_at in results do
    local time = os.date("%Y-%m-%d %H:%M", created_at)
    print(string.format("[%d] %s (%s) %s", id, time, source, sketch:sub(1, 60)))
  end
end

local function do_show(id_or_hash)
  local id = resolve_id(id_or_hash)
  if not id then
    io.stderr:write("pad: object not found: " .. id_or_hash .. "\n")
    os.exit(1)
  end
  local obj = pad.get_object(id)
  if not obj then
    io.stderr:write("pad: object not found: " .. id_or_hash .. "\n")
    os.exit(1)
  end
  print(string.format("id:       %d", obj.id))
  print(string.format("hash:     %s", obj.hash))
  print(string.format("tier:     %s", obj.tier))
  print(string.format("shape:    %s", obj.shape))
  print(string.format("size:     %d bytes", obj.size))
  print(string.format("coldness: %.3f", obj.coldness))
  print(string.format("accessed: %d times", obj.access_count))
  print(string.format("created:  %s", os.date("%Y-%m-%d %H:%M:%S", obj.created_at)))
  if obj.last_accessed_at then
    print(string.format("last:     %s", os.date("%Y-%m-%d %H:%M:%S", obj.last_accessed_at)))
  end
  -- annotations
  for key, value in pad.query("SELECT key, value FROM annotations WHERE object_id = ?;", obj.id) do
    print(string.format("@%-8s %s", key, value))
  end
  -- edges
  for _, to_id, relation in pad.query("SELECT id, to_id, relation FROM edges WHERE from_id = ?;", obj.id) do
    print(string.format("-> [%d] %s", to_id, relation))
  end
  for _, from_id, relation in pad.query("SELECT id, from_id, relation FROM edges WHERE to_id = ?;", obj.id) do
    print(string.format("<- [%d] %s", from_id, relation))
  end
  -- content
  print("")
  if obj.payload then
    print(obj.payload)
  else
    print(obj.sketch)
  end
end

local function do_history()
  local results = pad.query([[
    SELECT e.id, e.created_at, e.source, COALESCE(e.command, '') as command,
           (SELECT COUNT(*) FROM objects o WHERE o.event_id = e.id) as obj_count
    FROM events e
    ORDER BY e.created_at DESC
    LIMIT 30;
  ]])
  for id, created_at, source, command, obj_count in results do
    local time = os.date("%Y-%m-%d %H:%M:%S", created_at)
    local desc = #command > 0 and ("$ " .. command) or ""
    print(string.format("e%-4d %s [%-8s] %s (%d obj)", id, time, source, desc, obj_count))
  end
end

local function do_sources()
  local results = pad.query([[
    SELECT source, COUNT(*) as event_count, MAX(created_at) as last_seen
    FROM events
    GROUP BY source
    ORDER BY event_count DESC;
  ]])
  for source, count, last_seen in results do
    local time = os.date("%Y-%m-%d %H:%M", last_seen)
    print(string.format("%-12s %4d events  (last: %s)", source, count, time))
  end
end

local function do_note(text)
  if text == true then
    io.stderr:write("pad: enter note (ctrl+d to finish)\n")
    text = io.stdin:read("*a")
  end
  if text and #text > 0 then
    local id, hash = pad.ingest(text, { source = "note" })
    io.stderr:write(string.format("pad: note -> object %d (%s)\n", id, hash))
  end
end

local function do_tag(spec)
  local id_str, tag = spec:match("^(.+):(.+)$")
  if not id_str or not tag then
    io.stderr:write("usage: pad --tag <id>:<tag>\n")
    os.exit(1)
  end
  local id = resolve_id(id_str)
  if not id then
    io.stderr:write("pad: object not found: " .. id_str .. "\n")
    os.exit(1)
  end
  pad.annotate({ object_id = id, key = "tag", value = tag })
  io.stderr:write(string.format("pad: tagged [%d] '%s'\n", id, tag))
end

local function do_untag(spec)
  local id_str, tag = spec:match("^(.+):(.+)$")
  if not id_str or not tag then
    io.stderr:write("usage: pad --untag <id>:<tag>\n")
    os.exit(1)
  end
  local id = resolve_id(id_str)
  if not id then
    io.stderr:write("pad: object not found: " .. id_str .. "\n")
    os.exit(1)
  end
  pad.remove_annotation({ object_id = id, key = "tag", value = tag })
  io.stderr:write(string.format("pad: untagged [%d] '%s'\n", id, tag))
end

local function do_tagged(tag)
  local results = pad.query([[
    SELECT o.id, o.shape, o.sketch FROM objects o
    JOIN annotations a ON a.object_id = o.id
    WHERE a.key = 'tag' AND a.value = ?
    ORDER BY o.created_at DESC;
  ]], tag)
  for id, shape, sketch in results do
    print(string.format("[%d] (%s) %s", id, shape, sketch:sub(1, 60)))
  end
end

local function do_recall(pattern)
  local results = pad.query([[
    SELECT o.id, o.sketch, e.command, e.created_at FROM objects o
    JOIN events e ON e.id = o.event_id
    WHERE e.source = 'command' AND e.command LIKE ?
    ORDER BY e.created_at DESC
    LIMIT 20;
  ]], "%" .. pattern .. "%")
  for id, sketch, command, created_at in results do
    local time = os.date("%Y-%m-%d %H:%M", created_at)
    print(string.format("[%d] %s $ %s", id, time, command))
    print(string.format("     %s", sketch:sub(1, 70)))
  end
end

local function do_stats()
  local function count(sql)
    local iter = pad.query(sql)
    return iter()
  end
  local objects = count("SELECT COUNT(*) FROM objects;")
  local events = count("SELECT COUNT(*) FROM events;")
  local edges = count("SELECT COUNT(*) FROM edges;")
  local annotations = count("SELECT COUNT(*) FROM annotations;")
  local total_size = count("SELECT COALESCE(SUM(size), 0) FROM objects;")
  local avg_coldness = count("SELECT COALESCE(AVG(coldness), 0) FROM objects;")
  print(string.format("objects:      %d", objects))
  print(string.format("events:       %d", events))
  print(string.format("edges:        %d", edges))
  print(string.format("annotations:  %d", annotations))
  print(string.format("total size:   %d bytes", total_size))
  print(string.format("avg coldness: %.3f", avg_coldness))
end

local function do_orphans()
  local results = pad.query([[
    SELECT o.id, o.shape, o.sketch, o.coldness FROM objects o
    WHERE o.id NOT IN (SELECT from_id FROM edges)
      AND o.id NOT IN (SELECT to_id FROM edges)
    ORDER BY o.coldness DESC, o.created_at ASC
    LIMIT 20;
  ]])
  for id, shape, sketch, coldness in results do
    print(string.format("[%d] (%.2f) (%s) %s", id, coldness, shape, sketch:sub(1, 60)))
  end
end

local function do_vacuum()
  pad.recalculate_coldness()
  io.stderr:write("pad: coldness recalculated\n")
end

local function do_gc(confirm)
  pad.recalculate_coldness()
  local candidates = {}
  for id, hash, shape, sketch, coldness, size in pad.gc_candidates() do
    candidates[#candidates + 1] = { id = id, hash = hash, shape = shape, sketch = sketch, coldness = coldness, size = size }
  end
  if #candidates == 0 then
    io.stderr:write("pad: no GC candidates (coldness >= 0.9, no edges, no annotations)\n")
    return
  end
  for _, c in ipairs(candidates) do
    print(string.format("[%d] (%.2f) (%s) %d bytes  %s", c.id, c.coldness, c.shape, c.size, c.sketch:sub(1, 50)))
  end
  if confirm then
    for _, c in ipairs(candidates) do
      pad.gc_delete(c.id)
    end
    io.stderr:write(string.format("pad: deleted %d objects\n", #candidates))
  else
    io.stderr:write(string.format("pad: %d candidates (use --gc --confirm to delete)\n", #candidates))
  end
end

local function do_urgent()
  -- recently ingested, not yet accessed (access_count = 1 means only creation)
  local results = pad.query([[
    SELECT o.id, o.shape, o.sketch, e.source, e.created_at
    FROM objects o
    JOIN events e ON e.id = o.event_id
    WHERE o.access_count <= 1
    ORDER BY e.created_at DESC
    LIMIT 20;
  ]])
  local unreviewed = {}
  for id, shape, sketch, source, created_at in results do
    unreviewed[#unreviewed + 1] = { id = id, shape = shape, sketch = sketch, source = source, created_at = created_at }
  end

  -- objects tagged with "todo" or "deadline"
  local tagged = pad.query([[
    SELECT o.id, o.shape, o.sketch, a.key, a.value
    FROM objects o
    JOIN annotations a ON a.object_id = o.id
    WHERE a.key = 'tag' AND a.value IN ('todo', 'urgent', 'deadline')
    ORDER BY o.created_at DESC;
  ]])
  local action_items = {}
  for id, shape, sketch, key, value in tagged do
    action_items[#action_items + 1] = { id = id, shape = shape, sketch = sketch, tag = value }
  end

  if #action_items > 0 then
    print("-- action items --")
    for _, item in ipairs(action_items) do
      print(string.format("[%d] @%-8s (%s) %s", item.id, item.tag, item.shape, item.sketch:sub(1, 60)))
    end
  end

  if #unreviewed > 0 then
    print("-- unreviewed --")
    for _, item in ipairs(unreviewed) do
      local time = os.date("%Y-%m-%d %H:%M", item.created_at)
      print(string.format("[%d] %s (%s) %s", item.id, time, item.source, item.sketch:sub(1, 60)))
    end
  end

  if #action_items == 0 and #unreviewed == 0 then
    io.stderr:write("pad: nothing urgent\n")
  end
end

local function do_clip()
  if not clipboard then
    io.stderr:write("pad: clipboard extension not available\n")
    os.exit(1)
  end
  local content, info = clipboard.read()
  if not content then
    io.stderr:write("pad: " .. info .. "\n")
    os.exit(1)
  end
  local id, hash = pad.ingest(content, { source = "clipboard", metadata = { clipboard_tool = info } })
  io.stderr:write(string.format("pad: clipboard -> [%d] %s (%d bytes)\n", id, hash, #content))
end

local function do_git_log(n)
  if not git_ext then
    io.stderr:write("pad: git extension not available\n")
    os.exit(1)
  end
  if not git_ext.is_repo() then
    io.stderr:write("pad: not a git repository\n")
    os.exit(1)
  end
  n = tonumber(n) or 20
  local output = git_ext.log_full(n)
  if not output then
    io.stderr:write("pad: no git log output\n")
    return
  end
  local id, hash = pad.ingest(output, { source = "git:log", command = "git log -" .. n })
  io.stderr:write(string.format("pad: git log -> [%d] %s\n", id, hash))
end

local function do_git_diff(ref)
  if not git_ext then
    io.stderr:write("pad: git extension not available\n")
    os.exit(1)
  end
  if not git_ext.is_repo() then
    io.stderr:write("pad: not a git repository\n")
    os.exit(1)
  end
  local r = type(ref) == "string" and ref or nil
  local output = git_ext.diff(r)
  if not output then
    io.stderr:write("pad: no diff output\n")
    return
  end
  local id, hash = pad.ingest(output, { source = "git:diff", command = "git diff" .. (r and " " .. r or "") })
  io.stderr:write(string.format("pad: git diff -> [%d] %s\n", id, hash))
end

local function do_git_status()
  if not git_ext then
    io.stderr:write("pad: git extension not available\n")
    os.exit(1)
  end
  if not git_ext.is_repo() then
    io.stderr:write("pad: not a git repository\n")
    os.exit(1)
  end
  local output = git_ext.status()
  if not output then
    io.stderr:write("pad: working tree clean\n")
    return
  end
  local id, hash = pad.ingest(output, { source = "git:status", command = "git status --short" })
  io.stderr:write(string.format("pad: git status -> [%d] %s\n", id, hash))
end

local function do_watch(path)
  if path == true then
    io.stderr:write("usage: pad --watch <path>\n")
    os.exit(1)
  end
  -- resolve to absolute path
  if not path:match("^/") then
    local cwd = require("dep.get_cwd").get_cwd()
    path = cwd .. "/" .. path
  end
  local ok, err = pcall(pad.add_watch, path)
  if not ok then
    io.stderr:write("pad: " .. tostring(err) .. "\n")
    os.exit(1)
  end
  io.stderr:write("pad: watching " .. path .. "\n")
end

local function do_unwatch(path)
  if path == true then
    io.stderr:write("usage: pad --unwatch <path>\n")
    os.exit(1)
  end
  if not path:match("^/") then
    local cwd = require("dep.get_cwd").get_cwd()
    path = cwd .. "/" .. path
  end
  pad.remove_watch(path)
  io.stderr:write("pad: unwatched " .. path .. "\n")
end

local function do_watching()
  local count = 0
  for id, path, created_at in pad.list_watches() do
    local time = os.date("%Y-%m-%d %H:%M", created_at)
    print(string.format("[%d] %s  %s", id, time, path))
    count = count + 1
  end
  if count == 0 then
    io.stderr:write("pad: no file watches\n")
  end
end

local function do_daemon(flags)
  if flags.stop then
    daemon.stop()
  elseif flags.status then
    daemon.status()
  else
    daemon.run(pad, clipboard, flags.foreground)
  end
end

-- main

local function main(args)
  local flags, cmd_args = parse_args(args)

  if flags.search then
    do_search(flags.search)
  elseif flags.show then
    do_show(flags.show)
  elseif flags.recent then
    do_recent()
  elseif flags.history then
    do_history()
  elseif flags.sources then
    do_sources()
  elseif flags.note then
    do_note(flags.note)
  elseif flags.tag then
    do_tag(flags.tag)
  elseif flags.untag then
    do_untag(flags.untag)
  elseif flags.tagged then
    do_tagged(flags.tagged)
  elseif flags.recall then
    do_recall(flags.recall)
  elseif flags.stats then
    do_stats()
  elseif flags.orphans then
    do_orphans()
  elseif flags.gc then
    do_gc(flags.confirm)
  elseif flags.vacuum then
    do_vacuum()
  elseif flags.urgent then
    do_urgent()
  elseif flags.clip then
    do_clip()
  elseif flags["git-log"] then
    do_git_log(flags["git-log"])
  elseif flags["git-diff"] then
    do_git_diff(flags["git-diff"])
  elseif flags["git-status"] then
    do_git_status()
  elseif flags.watch then
    do_watch(flags.watch)
  elseif flags.unwatch then
    do_unwatch(flags.unwatch)
  elseif flags.watching then
    do_watching()
  elseif flags.daemon then
    do_daemon(flags)
  elseif #cmd_args > 0 then
    -- shell wrapper: run command, capture output, log event
    local full_cmd = table.concat(cmd_args, " ")
    local real_args, wrappers = unwrap.unwrap(cmd_args)
    local real_cmd = table.concat(real_args, " ")
    local base = unwrap.base_command(real_args)

    local handle = io.popen(full_cmd .. " 2>&1")
    if handle then
      local output = handle:read("*a")
      handle:close()
      if output and #output > 0 then
        -- check for parser
        local parsed = parsers and base and parsers.parse(base, output, real_args)

        local meta
        if #wrappers > 0 then
          meta = { full_command = full_cmd, wrapper = table.concat(wrappers, ", ") }
        end

        local id, hash = pad.ingest(output, {
          source = "command",
          command = real_cmd,
          shape = parsed and parsed.shape or nil,
          metadata = meta,
        })

        -- apply parser annotations
        if parsed and parsed.annotations then
          for k, v in pairs(parsed.annotations) do
            if v then pad.annotate({ object_id = id, key = k, value = v }) end
          end
        end
      end
      io.write(output)
    end
  elseif not is_tty() then
    -- stdin sink (silent on pipe)
    local content = io.stdin:read("*a")
    if content and #content > 0 then
      pad.ingest(content, { source = "stdin" })
    end
  else
    -- interactive REPL
    local repl_commands = {
      search = do_search,
      show = do_show,
      recent = function() do_recent() end,
      history = function() do_history() end,
      sources = function() do_sources() end,
      note = do_note,
      tag = do_tag,
      untag = do_untag,
      tagged = do_tagged,
      recall = do_recall,
      stats = function() do_stats() end,
      orphans = function() do_orphans() end,
      vacuum = function() do_vacuum() end,
      gc = function() do_gc(false) end,
      urgent = function() do_urgent() end,
      clip = function() do_clip() end,
      ["git-log"] = function(n) do_git_log(n) end,
      ["git-diff"] = function(ref) do_git_diff(ref) end,
      ["git-status"] = function() do_git_status() end,
      watch = do_watch,
      unwatch = do_unwatch,
      watching = function() do_watching() end,
    }
    io.stderr:write("pad: interactive mode (type text for notes, /command for operations, ctrl+d to exit)\n")
    while true do
      io.stderr:write("> ")
      local line = io.stdin:read("*l")
      if not line then break end
      local trimmed = line:match("^%s*(.-)%s*$")
      if #trimmed == 0 then
        -- skip empty lines
      elseif trimmed:match("^/") then
        local cmd, rest = trimmed:match("^/(%S+)%s*(.*)")
        if cmd == "quit" or cmd == "exit" or cmd == "q" then
          break
        elseif cmd == "help" then
          print("commands: /search /show /recent /history /sources /note /tag /untag /tagged /recall /stats /orphans /vacuum /gc /urgent /clip /git-log /git-diff /git-status /watch /unwatch /watching /quit")
          print("anything else is captured as a note")
        elseif repl_commands[cmd] then
          local arg = #rest > 0 and rest or nil
          local ok, err = pcall(repl_commands[cmd], arg or true)
          if not ok then io.stderr:write("error: " .. tostring(err) .. "\n") end
        else
          io.stderr:write("pad: unknown command /" .. cmd .. " (try /help)\n")
        end
      else
        -- default: capture as note
        local id, hash = pad.ingest(trimmed, { source = "note" })
        io.stderr:write(string.format("pad: note -> [%d] %s\n", id, hash))
      end
    end
  end
end

main(arg)
