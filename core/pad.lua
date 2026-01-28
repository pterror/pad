#!/usr/bin/env luajit
--[[
pad - cognitive stdin sink

usage:
  ... | pad              # ingest from stdin
  pad <cmd> [args...]    # exec wrapper
  pad query "..."        # query the graph
]]

package.path = package.path .. ";./?.lua;./?/init.lua"

local pad = require("pad.core")

local function is_tty()
  local _, code = os.execute("test -t 0")
  return code == 0
end

local function main(args)
  local cmd = args[1]

  if cmd == "query" then
    -- query mode
    local query = args[2]
    if not query then
      io.stderr:write("usage: pad query \"...\"\n")
      os.exit(1)
    end
    -- search sketches, ordered by effective coldness (warmer first)
    local now = os.time()
    local results = pad.query([[
      SELECT id, shape, sketch FROM objects
      WHERE sketch LIKE ?
      ORDER BY
        coldness + ((? - COALESCE(last_accessed_at, created_at)) / 86400.0 * 0.001) ASC,
        created_at DESC
      LIMIT 20;
    ]], "%" .. query .. "%", now)
    for id, shape, sketch in results do
      print(string.format("[%d] (%s) %s", id, shape, sketch:sub(1, 80)))
    end

  elseif cmd then
    -- exec wrapper mode: run command and capture output
    local full_cmd = table.concat(args, " ")
    local handle = io.popen(full_cmd .. " 2>&1")
    if handle then
      local output = handle:read("*a")
      handle:close()
      -- ingest the output
      pad.ingest(output, {
        source = "exec",
        command = full_cmd,
      })
      -- also print it through
      io.write(output)
    end

  else
    -- stdin sink mode
    if is_tty() then
      io.stderr:write("pad: reading from stdin (ctrl+d to finish)\n")
    end
    local content = io.stdin:read("*a")
    if content and #content > 0 then
      local id, hash = pad.ingest(content, { source = "stdin" })
      if is_tty() then
        io.stderr:write(string.format("pad: ingested %d bytes → object %d (%s)\n", #content, id, hash))
      end
    end
  end
end

main(arg)
