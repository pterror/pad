--[[
pad core - compositions of primitives

rules enforced via ops + validators:
1. capture is tiered (event/sketch/full)
2. content is content-addressed and deduped
3. budgets are enforced by validators
4. every object has provenance
5. coldness exists
]]

local sqlite = require("dep.sqlite")
local json = require("dep.lunajson")
local schema = require("pad.schema")
local get_cwd = require("dep.get_cwd").get_cwd
local xxhash = require("dep.xxhash")
local ops = require("pad.ops")
local validate = require("pad.validate")

local mod = {}

-- budgets (enforced by validators)
mod.budgets = {
  max_objects_per_event = 1000,
  max_edges_per_event = 5000,
  max_payload_bytes = 1024 * 1024,
  max_ms_per_event = 5000,
}

-- tier thresholds
mod.tiers = {
  sketch_threshold = 4096,
}

-- warmth deltas
mod.warmth = {
  on_access = 0.1,
  on_dedup = 0.05,
}

-- database
local dir = os.getenv("PAD_DIR") or (os.getenv("HOME") .. "/.pad")
local db_path = dir .. "/pad.db"
os.execute("mkdir -p " .. dir)
local db = sqlite.open(db_path)
if not db then error("pad: could not open database at " .. db_path) end
mod.db = db
db:execute(schema.init_sql)

-- Auto-rebuild FTS index if empty but objects exist (migration)
local function check_fts_migration()
  local fts_count = ops.fts_count(db)
  if fts_count == 0 then
    local iter = ops.query(db, "SELECT COUNT(*) FROM objects;")
    local obj_count = iter()
    if obj_count > 0 then
      ops.rebuild_fts(db)
    end
  end
end
check_fts_migration()

-- pure functions (no state, no db)

function mod.hash(data)
  return xxhash.hash(data)
end

function mod.make_sketch(content, size)
  local preview = content:sub(1, 256)
  if size > 256 then preview = preview .. "..." end
  return json.encode({
    preview = preview,
    size = size,
    lines = select(2, content:gsub("\n", "\n")) + 1,
  })
end

function mod.detect_shape(content)
  local trimmed = content:match("^%s*(.-)%s*$")
  if trimmed:match("^%[") and trimmed:match("%]$") then return "list"
  elseif trimmed:match("^{") and trimmed:match("}$") then return "object"
  elseif content:match("\t") and content:match("\n") then return "table"
  elseif content:match("^%d%d%d%d%-%d%d%-%d%d") or content:match("%[%d+%]") or content:match("^%w+ %d+ %d+:%d+") then return "log"
  elseif content:match("^/") or content:match("^%a:\\") or content:match("^file://") then return "path"
  elseif content:match("^https?://") then return "url"
  else return "text" end
end

-- composed operations

function mod.create_event(opts)
  validate.source(opts.source)
  local now = os.time()
  local cwd = opts.cwd or os.getenv("PAD_CWD") or get_cwd()
  local event_id = ops.insert_event(db, now, cwd, opts.command, opts.source)
  if opts.metadata then
    for k, v in pairs(opts.metadata) do
      ops.insert_annotation(db, event_id, nil, k, tostring(v), now)
    end
  end
  return event_id
end

function mod.ingest(content, opts)
  opts = opts or {}
  validate.source(opts.source)
  local now = os.time()
  local size = #content
  local hash = mod.hash(content)

  -- dedup: warm existing, always record provenance
  local existing_id = ops.find_by_hash(db, hash)
  if existing_id then
    ops.warm_object(db, existing_id, mod.warmth.on_dedup, now)
    local event_id = mod.create_event(opts)
    ops.insert_annotation(db, event_id, nil, "dedup_object_id", tostring(existing_id), now)
    return existing_id, hash
  end

  -- tier decision
  local tier, warning = validate.tier(size, opts.force_full, mod.tiers, mod.budgets)
  local payload = tier == "full" and content or nil

  -- shape + sketch
  local shape = opts.shape or mod.detect_shape(content)
  local sketch = mod.make_sketch(content, size)

  -- persist
  local event_id = mod.create_event(opts)
  if warning then
    ops.insert_annotation(db, event_id, nil, "warning", warning, now)
  end
  local object_id = ops.insert_object(db, hash, event_id, tier, shape, sketch, payload, size, now)

  return object_id, hash
end

function mod.link(from_id, to_id, relation, event_id)
  validate.edge(from_id, to_id, relation, event_id)
  validate.relation(relation)
  local count = ops.count_edges_for_event(db, event_id)
  validate.budget_edges(count, mod.budgets)
  return ops.insert_edge(db, event_id, from_id, to_id, relation, os.time())
end

function mod.annotate(opts)
  validate.annotation(opts)
  return ops.insert_annotation(db, opts.event_id, opts.object_id, opts.key, opts.value, os.time())
end

function mod.get_object(id)
  ops.warm_object(db, id, mod.warmth.on_access, os.time())
  return ops.fetch_object(db, id)
end

function mod.get_object_by_hash(prefix)
  local id = ops.find_by_hash_prefix(db, prefix)
  if not id then return nil end
  return mod.get_object(id)
end

function mod.find_by_hash_prefix(prefix)
  return ops.find_by_hash_prefix(db, prefix)
end

function mod.remove_annotation(opts)
  if not opts.object_id then error("pad: remove_annotation requires object_id") end
  if not opts.key then error("pad: remove_annotation requires key") end
  if not opts.value then error("pad: remove_annotation requires value") end
  ops.delete_annotation(db, opts.object_id, opts.key, opts.value)
end

function mod.recalculate_coldness()
  ops.age_cool_all(db, os.time(), 0.01)
end

function mod.create_sketch(object_id, content, opts)
  opts = opts or {}
  local source = opts.source or "sketch"
  local size = #content
  local hash = mod.hash(content)

  local existing_id = ops.find_by_hash(db, hash)
  if existing_id then
    ops.warm_object(db, existing_id, mod.warmth.on_dedup, os.time())
    return existing_id, hash
  end

  local event_id = mod.create_event({ source = source })
  local sketch_sketch = mod.make_sketch(content, size)
  local tier, warning = validate.tier(size, opts.force_full, mod.tiers, mod.budgets)
  local payload = tier == "full" and content or nil

  if warning then
    ops.insert_annotation(db, event_id, nil, "warning", warning, os.time())
  end

  local sketch_id = ops.insert_object(db, hash, event_id, tier, "text", sketch_sketch, payload, size, os.time())

  validate.edge(sketch_id, object_id, "sketch_of", event_id)
  validate.relation("sketch_of")
  ops.insert_edge(db, event_id, sketch_id, object_id, "sketch_of", os.time())

  return sketch_id, hash
end

function mod.get_sketches(object_id)
  return ops.query(db, [[
    SELECT o.id, o.sketch, o.payload, o.created_at
    FROM objects o
    JOIN edges e ON e.from_id = o.id
    WHERE e.to_id = ? AND e.relation = 'sketch_of'
    ORDER BY o.created_at DESC;
  ]], object_id)
end

function mod.gc_candidates(min_coldness)
  min_coldness = min_coldness or 0.9
  return ops.query(db, [[
    SELECT o.id, o.hash, o.shape, o.sketch, o.coldness, o.size FROM objects o
    WHERE o.coldness >= ?
      AND o.id NOT IN (SELECT from_id FROM edges)
      AND o.id NOT IN (SELECT to_id FROM edges)
      AND o.id NOT IN (SELECT DISTINCT object_id FROM annotations WHERE object_id IS NOT NULL)
    ORDER BY o.coldness DESC, o.created_at ASC;
  ]], min_coldness)
end

function mod.gc_delete(id)
  ops.delete_edges_for_object(db, id)
  ops.delete_annotations_for_object(db, id)
  ops.delete_object(db, id)
end

function mod.add_watch(path)
  validate.watch_path(path)
  -- check for existing watch (UNIQUE constraint)
  local iter = ops.query(db, "SELECT id FROM watches WHERE path = ?;", path)
  if iter() then
    error("pad: watch already exists for path: " .. path)
  end
  return ops.insert_watch(db, path, os.time())
end

function mod.remove_watch(path)
  validate.watch_path(path)
  ops.delete_watch(db, path)
end

function mod.list_watches()
  return ops.fetch_watches(db)
end

function mod.query(sql, ...)
  return ops.query(db, sql, ...)
end

function mod.search(term, limit)
  return ops.search_fts(db, term, limit or 20)
end

function mod.rebuild_fts()
  ops.rebuild_fts(db)
end

return mod
