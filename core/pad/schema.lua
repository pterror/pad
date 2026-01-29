--[[
pad schema - the 4-table data model

events      -- provenance (when, where, how something entered)
objects     -- content-addressed nodes (the actual data)
edges       -- relations between objects
annotations -- k/v metadata on events or objects
]]

local mod = {}

mod.init_sql = [[
  -- events: provenance records
  CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY,
    created_at INTEGER NOT NULL,      -- unix timestamp
    cwd TEXT,                         -- working directory at capture time
    command TEXT,                     -- command that produced this (if exec wrapper)
    source TEXT                       -- 'stdin' | 'exec' | 'file' | etc
  );

  -- objects: content-addressed nodes
  CREATE TABLE IF NOT EXISTS objects (
    id INTEGER PRIMARY KEY,
    hash TEXT UNIQUE NOT NULL,        -- content hash (dedup gate)
    event_id INTEGER NOT NULL,        -- provenance link (required!)
    tier TEXT NOT NULL,               -- 'event' | 'sketch' | 'full'
    shape TEXT,                       -- 'list' | 'table' | 'log' | 'blob' | 'text' | etc
    sketch TEXT,                      -- always present: summary/preview
    payload TEXT,                     -- full content (only if tier='full')
    size INTEGER,                     -- original size in bytes
    coldness REAL DEFAULT 0,          -- decay weight for retrieval ranking (0=hot, 1=cold)
    last_accessed_at INTEGER,         -- when object was last retrieved
    access_count INTEGER DEFAULT 0,   -- how many times accessed
    created_at INTEGER NOT NULL,
    FOREIGN KEY (event_id) REFERENCES events(id)
  );

  -- edges: relations between objects
  CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY,
    event_id INTEGER NOT NULL,        -- provenance
    from_id INTEGER NOT NULL,
    to_id INTEGER NOT NULL,
    relation TEXT NOT NULL,           -- 'derived_from' | 'contains' | 'references' | etc
    created_at INTEGER NOT NULL,
    FOREIGN KEY (event_id) REFERENCES events(id),
    FOREIGN KEY (from_id) REFERENCES objects(id),
    FOREIGN KEY (to_id) REFERENCES objects(id)
  );

  -- annotations: k/v metadata
  CREATE TABLE IF NOT EXISTS annotations (
    id INTEGER PRIMARY KEY,
    event_id INTEGER,                 -- if annotating an event
    object_id INTEGER,                -- if annotating an object
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (event_id) REFERENCES events(id),
    FOREIGN KEY (object_id) REFERENCES objects(id),
    CHECK (event_id IS NOT NULL OR object_id IS NOT NULL)
  );

  -- watches: inotify file watches
  CREATE TABLE IF NOT EXISTS watches (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL
  );

  -- indexes for common queries
  CREATE INDEX IF NOT EXISTS idx_objects_hash ON objects(hash);
  CREATE INDEX IF NOT EXISTS idx_objects_event ON objects(event_id);
  CREATE INDEX IF NOT EXISTS idx_objects_shape ON objects(shape);
  CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_id);
  CREATE INDEX IF NOT EXISTS idx_edges_to ON edges(to_id);
  CREATE INDEX IF NOT EXISTS idx_edges_relation ON edges(relation);
  CREATE INDEX IF NOT EXISTS idx_annotations_object ON annotations(object_id);
  CREATE INDEX IF NOT EXISTS idx_annotations_key ON annotations(key);
  CREATE INDEX IF NOT EXISTS idx_objects_coldness ON objects(coldness);
]]

return mod
