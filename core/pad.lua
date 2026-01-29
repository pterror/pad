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
]]

package.path = package.path .. ";./?.lua;./?/init.lua"

local pad = require("pad.core")

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
  local now = os.time()
  local results = pad.query([[
    SELECT id, shape, sketch FROM objects
    WHERE sketch LIKE ?
    ORDER BY
      coldness + ((? - COALESCE(last_accessed_at, created_at)) / 86400.0 * 0.001) ASC,
      created_at DESC
    LIMIT 20;
  ]], "%" .. term .. "%", now)
  for id, shape, sketch in results do
    print(string.format("[%d] (%s) %s", id, shape, sketch:sub(1, 80)))
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
  -- future: gc orphans, compress cold objects
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
  elseif flags.vacuum then
    do_vacuum()
  elseif #cmd_args > 0 then
    -- shell wrapper: run command, capture output, log event
    local full_cmd = table.concat(cmd_args, " ")
    local handle = io.popen(full_cmd .. " 2>&1")
    if handle then
      local output = handle:read("*a")
      handle:close()
      if output and #output > 0 then
        pad.ingest(output, {
          source = "command",
          command = full_cmd,
        })
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
    -- interactive: future REPL + daemon
    io.stderr:write("pad: interactive mode (not yet implemented)\n")
    io.stderr:write("pad: reading from stdin (ctrl+d to finish)\n")
    local content = io.stdin:read("*a")
    if content and #content > 0 then
      local id, hash = pad.ingest(content, { source = "stdin" })
      io.stderr:write(string.format("pad: ingested %d bytes -> object %d (%s)\n", #content, id, hash))
    end
  end
end

main(arg)
