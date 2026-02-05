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
  local id = db:last_insert_rowid()
  -- Sync to FTS index
  db:execute(
    "INSERT INTO objects_fts (rowid, sketch) VALUES (?, ?);",
    id, sketch or ""
  )
  return id
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

function mod.find_by_hash_prefix(db, prefix)
  local iter = db:query("SELECT id FROM objects WHERE hash LIKE ? LIMIT 1;", prefix .. "%")
  return iter()
end

function mod.delete_annotation(db, object_id, key, value)
  db:execute(
    "DELETE FROM annotations WHERE object_id = ? AND key = ? AND value = ?;",
    object_id, key, value
  )
end

function mod.age_cool_all(db, now, rate)
  db:execute([[
    UPDATE objects SET
      coldness = MIN(1.0, coldness + (? - COALESCE(last_accessed_at, created_at)) / 86400.0 * ?)
    WHERE coldness < 1.0;
  ]], now, rate)
end

function mod.delete_object(db, id)
  -- Remove from FTS index
  db:execute("DELETE FROM objects_fts WHERE rowid = ?;", id)
  db:execute("DELETE FROM objects WHERE id = ?;", id)
end

function mod.delete_edges_for_object(db, id)
  db:execute("DELETE FROM edges WHERE from_id = ? OR to_id = ?;", id, id)
end

function mod.delete_annotations_for_object(db, id)
  db:execute("DELETE FROM annotations WHERE object_id = ?;", id)
end

function mod.count_objects_for_event(db, event_id)
  local iter = db:query("SELECT COUNT(*) FROM objects WHERE event_id = ?;", event_id)
  return iter()
end

function mod.count_edges_for_event(db, event_id)
  local iter = db:query("SELECT COUNT(*) FROM edges WHERE event_id = ?;", event_id)
  return iter()
end

function mod.insert_watch(db, path, created_at)
  db:execute(
    "INSERT INTO watches (path, created_at) VALUES (?, ?);",
    path, created_at
  )
  return db:last_insert_rowid()
end

function mod.delete_watch(db, path)
  db:execute("DELETE FROM watches WHERE path = ?;", path)
end

function mod.fetch_watches(db)
  return db:query("SELECT id, path, created_at FROM watches ORDER BY created_at;")
end

function mod.query(db, sql, ...)
  return db:query(sql, ...)
end

function mod.search_fts(db, term, limit)
  limit = limit or 20
  return db:query([[
    SELECT o.id, o.shape, o.sketch, bm25(objects_fts) as rank
    FROM objects_fts fts
    JOIN objects o ON o.id = fts.rowid
    WHERE objects_fts MATCH ?
    ORDER BY rank
    LIMIT ?;
  ]], term, limit)
end

function mod.rebuild_fts(db)
  -- Clear existing FTS entries
  db:execute("DELETE FROM objects_fts;")
  -- Rebuild from all objects
  db:execute([[
    INSERT INTO objects_fts (rowid, sketch)
    SELECT id, COALESCE(sketch, '') FROM objects;
  ]])
end

function mod.fts_count(db)
  local iter = db:query("SELECT COUNT(*) FROM objects_fts;")
  return iter()
end

return mod
