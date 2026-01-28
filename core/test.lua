#!/usr/bin/env luajit
--[[
Tests for pad core

Run: ./dep/luajit test.lua
]]

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

-- hash tests
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

-- schema tests (just verify SQL is valid)
test("schema: SQL parses", function()
  local schema = require("pad.schema")
  if not schema.init_sql or #schema.init_sql == 0 then
    error("schema.init_sql is empty")
  end
  -- check for new columns
  assert_match(schema.init_sql, "last_accessed_at", "should have last_accessed_at")
  assert_match(schema.init_sql, "access_count", "should have access_count")
  assert_match(schema.init_sql, "idx_objects_coldness", "should have coldness index")
end)

print("\n--- Tests complete ---")
