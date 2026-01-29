--[[
pad dispatch - shared JSON action dispatch for IPC

Used by both unix socket and WebSocket listeners.
Routes action tables to pad core calls, returns response tables.
]]

local json = require("dep.lunajson")

local mod = {}

function mod.dispatch(pad, action)
  if not action or type(action) ~= "table" then
    return { ok = false, error = "invalid action" }
  end

  local name = action.action
  if not name then
    return { ok = false, error = "missing action field" }
  end

  if name == "ingest" then
    if not action.content or #action.content == 0 then
      return { ok = false, error = "ingest requires content" }
    end
    local source = action.source or "ipc"
    local id, hash = pad.ingest(action.content, { source = source, metadata = action.metadata })
    return { ok = true, id = id, hash = hash }

  elseif name == "search" then
    if not action.term then
      return { ok = false, error = "search requires term" }
    end
    local now = os.time()
    local results = {}
    for id, shape, sketch in pad.query([[
      SELECT id, shape, sketch FROM objects
      WHERE sketch LIKE ?
      ORDER BY coldness ASC, created_at DESC
      LIMIT 20;
    ]], "%" .. action.term .. "%", now) do
      results[#results + 1] = { id = id, shape = shape, sketch = sketch }
    end
    return { ok = true, results = results }

  elseif name == "recent" then
    local results = {}
    for id, shape, sketch, source, created_at in pad.query([[
      SELECT o.id, o.shape, o.sketch, e.source, e.created_at
      FROM objects o JOIN events e ON e.id = o.event_id
      ORDER BY e.created_at DESC LIMIT 20;
    ]]) do
      results[#results + 1] = { id = id, shape = shape, sketch = sketch, source = source, created_at = created_at }
    end
    return { ok = true, results = results }

  elseif name == "show" then
    if not action.id then
      return { ok = false, error = "show requires id" }
    end
    local id = tonumber(action.id)
    if not id then
      id = pad.find_by_hash_prefix(action.id)
    end
    if not id then
      return { ok = false, error = "object not found" }
    end
    local obj = pad.get_object(id)
    if not obj then
      return { ok = false, error = "object not found" }
    end
    return { ok = true, object = obj }

  elseif name == "stats" then
    local function count(sql)
      local iter = pad.query(sql)
      return iter()
    end
    return {
      ok = true,
      objects = count("SELECT COUNT(*) FROM objects;"),
      events = count("SELECT COUNT(*) FROM events;"),
      edges = count("SELECT COUNT(*) FROM edges;"),
      annotations = count("SELECT COUNT(*) FROM annotations;"),
      total_size = count("SELECT COALESCE(SUM(size), 0) FROM objects;"),
    }

  elseif name == "note" then
    if not action.text or #action.text == 0 then
      return { ok = false, error = "note requires text" }
    end
    local id, hash = pad.ingest(action.text, { source = "note" })
    return { ok = true, id = id, hash = hash }

  elseif name == "tag" then
    if not action.id or not action.tag then
      return { ok = false, error = "tag requires id and tag" }
    end
    local id = tonumber(action.id)
    if not id then
      return { ok = false, error = "invalid id" }
    end
    pad.annotate({ object_id = id, key = "tag", value = action.tag })
    return { ok = true }

  elseif name == "untag" then
    if not action.id or not action.tag then
      return { ok = false, error = "untag requires id and tag" }
    end
    local id = tonumber(action.id)
    if not id then
      return { ok = false, error = "invalid id" }
    end
    pad.remove_annotation({ object_id = id, key = "tag", value = action.tag })
    return { ok = true }

  else
    return { ok = false, error = "unknown action: " .. tostring(name) }
  end
end

function mod.handle_line(pad, line)
  local ok, action = pcall(json.decode, line)
  if not ok then
    return json.encode({ ok = false, error = "invalid JSON" })
  end
  local ok2, result = pcall(mod.dispatch, pad, action)
  if not ok2 then
    return json.encode({ ok = false, error = tostring(result) })
  end
  return json.encode(result)
end

return mod
