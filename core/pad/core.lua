--[[
pad core - the heart

rules enforced here:
1. capture is tiered (event/sketch/full)
2. content is content-addressed and deduped
3. budgets are enforced in core
4. every object has provenance
5. coldness exists
]]

local sqlite = require("dep.sqlite")
local json = require("dep.lunajson")
local schema = require("pad.schema")
local get_cwd = require("dep.get_cwd").get_cwd

local mod = {}

-- budgets (enforced in core, not trusted to plugins)
mod.budgets = {
  max_objects_per_event = 1000,
  max_edges_per_event = 5000,
  max_payload_bytes = 1024 * 1024,  -- 1MB before sketch-only
  max_ms_per_event = 5000,
}

-- tier thresholds
mod.tiers = {
  sketch_threshold = 4096,  -- bytes above which we only keep sketch by default
}

local dir = os.getenv("PAD_DIR") or (os.getenv("HOME") .. "/.pad")
local db_path = dir .. "/pad.db"

-- ensure directory exists
os.execute("mkdir -p " .. dir)

local db = sqlite.open(db_path)
if not db then
  error("pad: could not open database at " .. db_path)
end

mod.db = db

-- init schema
db:execute(schema.init_sql)

--[[@param data string]]
--[[@return string hash]]
local function hash_content(data)
  -- simple djb2 hash for now, upgrade to sha256 later
  local h = 5381
  for i = 1, #data do
    h = ((h * 33) + data:byte(i)) % 0xFFFFFFFF
  end
  return string.format("%08x", h)
end

--[[@param content string]]
--[[@param size integer]]
--[[@return string sketch]]
local function make_sketch(content, size)
  -- first 256 chars + metadata
  local preview = content:sub(1, 256)
  if size > 256 then
    preview = preview .. "..."
  end
  return json.encode({
    preview = preview,
    size = size,
    lines = select(2, content:gsub("\n", "\n")) + 1,
  })
end

--[[@param content string]]
--[[@return string shape]]
local function detect_shape(content)
  -- simple heuristics for shape detection
  local first_char = content:sub(1, 1)
  local trimmed = content:match("^%s*(.-)%s*$")

  if trimmed:match("^%[") and trimmed:match("%]$") then
    return "list"
  elseif trimmed:match("^{") and trimmed:match("}$") then
    return "object"
  elseif content:match("\t") and content:match("\n") then
    return "table"
  elseif content:match("^%d%d%d%d%-%d%d%-%d%d") or content:match("%[%d+%]") or content:match("^%w+ %d+ %d+:%d+") then
    return "log"
  elseif content:match("^/") or content:match("^%a:\\") or content:match("^file://") then
    return "path"
  elseif content:match("^https?://") then
    return "url"
  else
    return "text"
  end
end

--[[
Create an event (provenance record)

@param opts table
  - source: string (required) - 'stdin' | 'clipboard' | 'browser' | 'git:commit' | etc
  - cwd: string (optional)
  - command: string (optional)
  - url: string (optional) - for browser source
  - metadata: table (optional) - additional provenance data
@return integer event_id
]]
function mod.create_event(opts)
  if not opts.source then
    error("pad: event requires source (invariant: no orphan provenance)")
  end

  local cwd = opts.cwd or get_cwd()
  local now = os.time()

  db:execute(
    "INSERT INTO events (created_at, cwd, command, source) VALUES (?, ?, ?, ?);",
    now, cwd, opts.command, opts.source
  )

  local event_id = db:last_insert_rowid()

  -- store extra metadata as annotations
  if opts.metadata then
    for k, v in pairs(opts.metadata) do
      db:execute(
        "INSERT INTO annotations (event_id, key, value, created_at) VALUES (?, ?, ?, ?);",
        event_id, k, tostring(v), now
      )
    end
  end

  return event_id
end

--[[
Ingest content into pad

@param content string - raw content
@param opts table
  - source: string (required) - identifies the tendril
  - force_full: boolean - override tier policy
  - shape: string - override shape detection
  - (plus any event opts)
@return integer object_id, string hash
]]
function mod.ingest(content, opts)
  opts = opts or {}

  if not opts.source then
    error("pad: ingest requires source (invariant: every object needs provenance)")
  end

  local size = #content
  local content_hash = hash_content(content)

  -- dedup check (invariant 2)
  local existing = db:query("SELECT id FROM objects WHERE hash = ?;", content_hash)
  local existing_id = existing()
  if existing_id then
    -- already exists, just return existing
    return existing_id, content_hash
  end

  -- create event
  local event_id = mod.create_event(opts)

  -- determine tier (invariant 1)
  local tier = "full"
  local payload = content

  if size > mod.budgets.max_payload_bytes then
    -- hard budget: sketch only, emit warning
    tier = "sketch"
    payload = nil
    db:execute(
      "INSERT INTO annotations (event_id, key, value, created_at) VALUES (?, ?, ?, ?);",
      event_id, "warning", "truncated_by_budget:max_payload_bytes", os.time()
    )
  elseif size > mod.tiers.sketch_threshold and not opts.force_full then
    -- soft threshold: sketch unless overridden
    tier = "sketch"
    payload = nil
  end

  -- detect shape (invariant 3: core classifies shapes, not formats)
  local shape = opts.shape or detect_shape(content)

  -- create sketch (always)
  local sketch = make_sketch(content, size)

  -- insert object
  db:execute([[
    INSERT INTO objects (hash, event_id, tier, shape, sketch, payload, size, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
  ]], content_hash, event_id, tier, shape, sketch, payload, size, os.time())

  return db:last_insert_rowid(), content_hash
end

--[[
Create an edge between objects

@param from_id integer
@param to_id integer
@param relation string - 'derived_from' | 'contains' | 'references' | etc
@param event_id integer - provenance
@return integer edge_id
]]
function mod.link(from_id, to_id, relation, event_id)
  if not event_id then
    error("pad: edge requires event_id (invariant: every derived object must be attributable)")
  end

  db:execute([[
    INSERT INTO edges (event_id, from_id, to_id, relation, created_at)
    VALUES (?, ?, ?, ?, ?);
  ]], event_id, from_id, to_id, relation, os.time())

  return db:last_insert_rowid()
end

--[[
Annotate an object or event

@param opts table
  - object_id: integer (optional)
  - event_id: integer (optional)
  - key: string (required)
  - value: string (required)
]]
function mod.annotate(opts)
  if not opts.object_id and not opts.event_id then
    error("pad: annotation requires object_id or event_id")
  end

  db:execute([[
    INSERT INTO annotations (event_id, object_id, key, value, created_at)
    VALUES (?, ?, ?, ?, ?);
  ]], opts.event_id, opts.object_id, opts.key, opts.value, os.time())
end

--[[
Simple query interface
]]
function mod.query(sql, ...)
  return db:query(sql, ...)
end

return mod
