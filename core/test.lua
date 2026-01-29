#!/usr/bin/env luajit
--[[
Tests for pad core

Run: cd core && luajit test.lua
]]

package.path = package.path .. ";./?.lua;./?/init.lua"

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("PASS: " .. name)
  else
    print("FAIL: " .. name)
    print("  " .. tostring(err))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assertion failed") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
  end
end

local function assert_match(str, pattern, msg)
  if not str:match(pattern) then
    error((msg or "match failed") .. ": '" .. str .. "' !~ /" .. pattern .. "/")
  end
end

-- hash tests (no db required)

test("hash: produces 16 hex chars", function()
  local xxhash = require("dep.xxhash")
  local h = xxhash.hash("hello")
  assert_eq(#h, 16, "hash length")
  assert_match(h, "^%x+$", "hex chars only")
end)

test("hash: deterministic", function()
  local xxhash = require("dep.xxhash")
  local h1 = xxhash.hash("test content")
  local h2 = xxhash.hash("test content")
  assert_eq(h1, h2, "same input = same hash")
end)

test("hash: different input = different hash", function()
  local xxhash = require("dep.xxhash")
  local h1 = xxhash.hash("hello")
  local h2 = xxhash.hash("world")
  if h1 == h2 then
    error("different inputs produced same hash")
  end
end)

test("hash: empty string works", function()
  local xxhash = require("dep.xxhash")
  local h = xxhash.hash("")
  assert_eq(#h, 16, "hash length for empty")
end)

test("hash: large input works", function()
  local xxhash = require("dep.xxhash")
  local big = string.rep("x", 100000)
  local h = xxhash.hash(big)
  assert_eq(#h, 16, "hash length for large input")
end)

-- schema tests (no db required)

test("schema: SQL parses", function()
  local schema = require("pad.schema")
  if not schema.init_sql or #schema.init_sql == 0 then
    error("schema.init_sql is empty")
  end
  assert_match(schema.init_sql, "last_accessed_at", "should have last_accessed_at")
  assert_match(schema.init_sql, "access_count", "should have access_count")
  assert_match(schema.init_sql, "idx_objects_coldness", "should have coldness index")
end)

-- validator tests (pure, no db)

test("validate: rejects nil source", function()
  local validate = require("pad.validate")
  local ok, err = pcall(validate.source, nil)
  assert(not ok, "should reject nil source")
  assert(tostring(err):match("source"), "error should mention source")
end)

test("validate: rejects empty source", function()
  local validate = require("pad.validate")
  local ok, err = pcall(validate.source, "")
  assert(not ok, "should reject empty source")
end)

test("validate: accepts valid source", function()
  local validate = require("pad.validate")
  assert(validate.source("stdin"), "should accept stdin")
  assert(validate.source("command"), "should accept command")
  assert(validate.source("git:commit"), "should accept extension sources")
end)

test("validate: tier full under threshold", function()
  local validate = require("pad.validate")
  local tier, warning = validate.tier(100, false, { sketch_threshold = 4096 }, { max_payload_bytes = 1024 * 1024 })
  assert_eq(tier, "full", "small content should be full")
  assert_eq(warning, nil, "no warning")
end)

test("validate: tier sketch over threshold", function()
  local validate = require("pad.validate")
  local tier, warning = validate.tier(5000, false, { sketch_threshold = 4096 }, { max_payload_bytes = 1024 * 1024 })
  assert_eq(tier, "sketch", "large content should be sketch")
  assert_eq(warning, nil, "no warning for soft threshold")
end)

test("validate: tier sketch with budget warning", function()
  local validate = require("pad.validate")
  local tier, warning = validate.tier(2000000, false, { sketch_threshold = 4096 }, { max_payload_bytes = 1024 * 1024 })
  assert_eq(tier, "sketch", "over-budget should be sketch")
  assert(warning, "should have budget warning")
end)

test("validate: tier force_full overrides threshold", function()
  local validate = require("pad.validate")
  local tier, warning = validate.tier(5000, true, { sketch_threshold = 4096 }, { max_payload_bytes = 1024 * 1024 })
  assert_eq(tier, "full", "force_full overrides soft threshold")
end)

test("validate: tier force_full cannot override hard budget", function()
  local validate = require("pad.validate")
  local tier, _ = validate.tier(2000000, true, { sketch_threshold = 4096 }, { max_payload_bytes = 1024 * 1024 })
  assert_eq(tier, "sketch", "hard budget wins over force_full")
end)

test("validate: edge rejects missing fields", function()
  local validate = require("pad.validate")
  local ok1 = pcall(validate.edge, nil, 2, "ref", 1)
  local ok2 = pcall(validate.edge, 1, nil, "ref", 1)
  local ok3 = pcall(validate.edge, 1, 2, nil, 1)
  local ok4 = pcall(validate.edge, 1, 2, "ref", nil)
  assert(not ok1, "should reject nil from_id")
  assert(not ok2, "should reject nil to_id")
  assert(not ok3, "should reject nil relation")
  assert(not ok4, "should reject nil event_id")
end)

test("validate: annotation rejects missing target", function()
  local validate = require("pad.validate")
  local ok = pcall(validate.annotation, { key = "k", value = "v" })
  assert(not ok, "should reject missing target")
end)

test("validate: budget_objects rejects over limit", function()
  local validate = require("pad.validate")
  local ok = pcall(validate.budget_objects, 1000, { max_objects_per_event = 1000 })
  assert(not ok, "should reject at limit")
  assert(validate.budget_objects(999, { max_objects_per_event = 1000 }), "should accept under limit")
end)

test("validate: budget_edges rejects over limit", function()
  local validate = require("pad.validate")
  local ok = pcall(validate.budget_edges, 5000, { max_edges_per_event = 5000 })
  assert(not ok, "should reject at limit")
  assert(validate.budget_edges(4999, { max_edges_per_event = 5000 }), "should accept under limit")
end)

test("validate: relation accepts known types", function()
  local validate = require("pad.validate")
  assert(validate.relation("supersedes"), "supersedes")
  assert(validate.relation("derived_from"), "derived_from")
  assert(validate.relation("references"), "references")
  assert(validate.relation("reply_to"), "reply_to")
  assert(validate.relation("sketch_of"), "sketch_of")
end)

test("validate: relation rejects unknown types", function()
  local validate = require("pad.validate")
  local ok = pcall(validate.relation, "invented_relation")
  assert(not ok, "should reject unknown relation")
end)

-- integration tests (require real sqlite)

-- isolate test db
local ffi = require("ffi")
pcall(function() ffi.cdef("int setenv(const char *name, const char *value, int overwrite);") end)
local test_dir = "/tmp/pad_test_" .. os.time()
ffi.C.setenv("PAD_DIR", test_dir, 1)

local pad = require("pad.core")

test("ingest: creates object and event", function()
  local id, hash = pad.ingest("hello world", { source = "test" })
  assert(id, "should return object id")
  assert(hash, "should return hash")
  assert_eq(#hash, 16, "hash length")
end)

test("ingest: stores payload for small content", function()
  local id, _ = pad.ingest("small content", { source = "test" })
  local obj = pad.get_object(id)
  assert_eq(obj.tier, "full", "small content should be full tier")
  assert_eq(obj.payload, "small content", "payload should match")
end)

test("ingest: detects shape", function()
  local id, _ = pad.ingest("https://example.com", { source = "test" })
  local obj = pad.get_object(id)
  assert_eq(obj.shape, "url", "should detect url shape")
end)

test("ingest: dedup returns same object id", function()
  local id1, hash1 = pad.ingest("dedup test content", { source = "test" })
  local id2, hash2 = pad.ingest("dedup test content", { source = "test" })
  assert_eq(id1, id2, "same content = same object")
  assert_eq(hash1, hash2, "same content = same hash")
end)

test("ingest: dedup records provenance for both sources", function()
  local unique = "provenance test " .. tostring(os.clock())
  pad.ingest(unique, { source = "test_a" })
  pad.ingest(unique, { source = "test_b" })
  local count = 0
  for _ in pad.query("SELECT id FROM events WHERE source IN ('test_a', 'test_b');") do
    count = count + 1
  end
  assert(count >= 2, "should have events from both sources, got " .. count)
end)

test("ingest: dedup warms object", function()
  local unique = "warmth test " .. tostring(os.clock())
  local id, _ = pad.ingest(unique, { source = "test" })
  local obj1 = pad.get_object(id)
  local c1 = obj1.coldness
  pad.ingest(unique, { source = "test" })
  local obj2 = pad.get_object(id)
  assert(obj2.access_count > obj1.access_count, "access count should increase")
end)

test("get_object: warms on access", function()
  local id, _ = pad.ingest("access test " .. tostring(os.clock()), { source = "test" })
  local obj1 = pad.get_object(id)
  local obj2 = pad.get_object(id)
  assert(obj2.access_count > obj1.access_count, "access count should increase on read")
end)

test("link: creates edge between objects", function()
  local id1, _ = pad.ingest("link from " .. tostring(os.clock()), { source = "test" })
  local id2, _ = pad.ingest("link to " .. tostring(os.clock()), { source = "test" })
  local event_id = pad.create_event({ source = "test" })
  local edge_id = pad.link(id1, id2, "references", event_id)
  assert(edge_id, "should return edge id")
end)

test("link: rejects missing event_id", function()
  local ok = pcall(pad.link, 1, 2, "references", nil)
  assert(not ok, "should reject edge without event_id")
end)

test("annotate: adds metadata to object", function()
  local id, _ = pad.ingest("annotate test " .. tostring(os.clock()), { source = "test" })
  pad.annotate({ object_id = id, key = "tag", value = "important" })
  local iter = pad.query("SELECT value FROM annotations WHERE object_id = ? AND key = 'tag';", id)
  local value = iter()
  assert_eq(value, "important", "annotation value")
end)

test("annotate: rejects missing target", function()
  local ok = pcall(pad.annotate, { key = "k", value = "v" })
  assert(not ok, "should reject annotation without target")
end)

test("detect_shape: text", function()
  assert_eq(pad.detect_shape("hello world"), "text")
end)

test("detect_shape: url", function()
  assert_eq(pad.detect_shape("https://example.com"), "url")
end)

test("detect_shape: list", function()
  assert_eq(pad.detect_shape("[1, 2, 3]"), "list")
end)

test("detect_shape: object", function()
  assert_eq(pad.detect_shape('{"key": "value"}'), "object")
end)

test("detect_shape: path", function()
  assert_eq(pad.detect_shape("/usr/local/bin"), "path")
end)

test("ingest: rejects missing source", function()
  local ok, err = pcall(pad.ingest, "no source", {})
  assert(not ok, "should reject missing source")
  assert(tostring(err):match("source"), "error should mention source")
end)

test("link: rejects unknown relation", function()
  local id1, _ = pad.ingest("rel from " .. tostring(os.clock()), { source = "test" })
  local id2, _ = pad.ingest("rel to " .. tostring(os.clock()), { source = "test" })
  local event_id = pad.create_event({ source = "test" })
  local ok = pcall(pad.link, id1, id2, "made_up", event_id)
  assert(not ok, "should reject unknown relation type")
end)

test("gc: cold orphan without annotations is a candidate", function()
  local id, _ = pad.ingest("gc test " .. tostring(os.clock()), { source = "test" })
  -- force coldness to 1.0
  pad.db:execute("UPDATE objects SET coldness = 1.0 WHERE id = ?;", id)
  -- remove any annotations on this object
  pad.db:execute("DELETE FROM annotations WHERE object_id = ?;", id)
  local found = false
  for cid in pad.gc_candidates(0.9) do
    if cid == id then found = true end
  end
  assert(found, "cold orphan should be a GC candidate")
end)

test("create_sketch: creates linked sketch object", function()
  local id, _ = pad.ingest("sketch target " .. tostring(os.clock()), { source = "test" })
  local sketch_id, sketch_hash = pad.create_sketch(id, "this is a summary of the target object")
  assert(sketch_id, "should return sketch object id")
  assert(sketch_hash, "should return sketch hash")
  -- verify edge exists
  local found = false
  for _, from_id, to_id, relation in pad.query("SELECT id, from_id, to_id, relation FROM edges WHERE from_id = ? AND to_id = ?;", sketch_id, id) do
    if relation == "sketch_of" then found = true end
  end
  assert(found, "should have sketch_of edge")
end)

test("get_sketches: returns linked sketches", function()
  local id, _ = pad.ingest("multi-sketch " .. tostring(os.clock()), { source = "test" })
  pad.create_sketch(id, "summary v1 " .. tostring(os.clock()))
  pad.create_sketch(id, "summary v2 " .. tostring(os.clock()))
  local count = 0
  for _ in pad.get_sketches(id) do count = count + 1 end
  assert(count >= 2, "should have at least 2 linked sketches, got " .. count)
end)

test("gc: gc_delete removes object", function()
  local id, _ = pad.ingest("gc delete " .. tostring(os.clock()), { source = "test" })
  pad.db:execute("UPDATE objects SET coldness = 1.0 WHERE id = ?;", id)
  pad.db:execute("DELETE FROM annotations WHERE object_id = ?;", id)
  pad.gc_delete(id)
  local obj = pad.get_object(id)
  assert(not obj, "object should be deleted after gc_delete")
end)

-- cleanup
os.execute("rm -rf " .. test_dir)

print("\n--- Tests complete ---")
