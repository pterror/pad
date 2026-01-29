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
  local cwd = opts.cwd or get_cwd()
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

function mod.query(sql, ...)
  return ops.query(db, sql, ...)
end

return mod
