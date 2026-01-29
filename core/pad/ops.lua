--[[
pad ops - atomic state mutations

The only code that writes to the database.
Each op is a single statement. No validation, no composition.
Lua scripts compose these, but cannot define invariants.
]]

local mod = {}

function mod.insert_event(db, created_at, cwd, command, source)
  db:execute(
    "INSERT INTO events (created_at, cwd, command, source) VALUES (?, ?, ?, ?);",
    created_at, cwd, command, source
  )
  return db:last_insert_rowid()
end

function mod.insert_object(db, hash, event_id, tier, shape, sketch, payload, size, created_at)
  db:execute(
    "INSERT INTO objects (hash, event_id, tier, shape, sketch, payload, size, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
    hash, event_id, tier, shape, sketch, payload, size, created_at
  )
  return db:last_insert_rowid()
end

function mod.insert_edge(db, event_id, from_id, to_id, relation, created_at)
  db:execute(
    "INSERT INTO edges (event_id, from_id, to_id, relation, created_at) VALUES (?, ?, ?, ?, ?);",
    event_id, from_id, to_id, relation, created_at
  )
  return db:last_insert_rowid()
end

function mod.insert_annotation(db, event_id, object_id, key, value, created_at)
  db:execute(
    "INSERT INTO annotations (event_id, object_id, key, value, created_at) VALUES (?, ?, ?, ?, ?);",
    event_id, object_id, key, value, created_at
  )
  return db:last_insert_rowid()
end

function mod.warm_object(db, id, amount, now)
  db:execute([[
    UPDATE objects SET
      last_accessed_at = ?,
      access_count = access_count + 1,
      coldness = MAX(0, coldness - ?)
    WHERE id = ?;
  ]], now, amount, id)
end

function mod.fetch_object(db, id)
  local iter = db:query([[
    SELECT id, hash, event_id, tier, shape, sketch, payload, size,
           coldness, last_accessed_at, access_count, created_at
    FROM objects WHERE id = ?;
  ]], id)
  local oid, hash, event_id, tier, shape, sketch, payload, size,
        coldness, last_accessed_at, access_count, created_at = iter()
  if not oid then return nil end
  return {
    id = oid, hash = hash, event_id = event_id,
    tier = tier, shape = shape, sketch = sketch, payload = payload,
    size = size, coldness = coldness, last_accessed_at = last_accessed_at,
    access_count = access_count, created_at = created_at,
  }
end

function mod.find_by_hash(db, hash)
  local iter = db:query("SELECT id FROM objects WHERE hash = ?;", hash)
  return iter()
end

function mod.query(db, sql, ...)
  return db:query(sql, ...)
end

return mod
