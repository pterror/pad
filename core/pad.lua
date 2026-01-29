#!/usr/bin/env luajit
--[[
pad - cognitive stdin sink

usage:
  ... | pad                  # ingest from stdin
  pad <cmd> [args...]        # shell wrapper (captures output)
  pad --search "..."         # search objects
  pad --recent               # recent captures
  pad --stats                # database stats
  pad --orphans              # unlinked objects
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

-- main

local function main(args)
  local flags, cmd_args = parse_args(args)

  if flags.search then
    do_search(flags.search)
  elseif flags.recent then
    do_recent()
  elseif flags.stats then
    do_stats()
  elseif flags.orphans then
    do_orphans()
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
