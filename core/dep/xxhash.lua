--[[
Content hash for pad

Tries xxHash64 via FFI, falls back to FNV-1a 64-bit in pure Lua.
Either way: 64-bit output (16 hex chars), low collision probability.
]]

local ffi = require("ffi")
local bit = require("bit")

local mod = {}

-- try to load xxhash
local xxhash_lib
local function try_xxhash()
  ffi.cdef [[
    typedef uint64_t XXH64_hash_t;
    XXH64_hash_t XXH64(const void* input, size_t length, XXH64_hash_t seed);
  ]]

  if ffi.os == "Windows" then
    if ffi.arch == "x64" then
      xxhash_lib = ffi.load("dep/xxhash.dll")
    else
      xxhash_lib = ffi.load("dep/xxhash-x86.dll")
    end
  else
    xxhash_lib = ffi.load("xxhash")
  end
end

local has_xxhash = pcall(try_xxhash)

if has_xxhash then
  -- fast path: use xxhash
  function mod.hash(data)
    local h = xxhash_lib.XXH64(data, #data, 0)
    return string.format("%016x", tonumber(h))
  end
else
  -- fallback: FNV-1a 64-bit in pure LuaJIT
  -- good distribution, simple, fast enough for local use
  local FNV_OFFSET = ffi.new("uint64_t", 0xcbf29ce484222325ULL)
  local FNV_PRIME = ffi.new("uint64_t", 0x100000001b3ULL)

  function mod.hash(data)
    local h = FNV_OFFSET
    for i = 1, #data do
      h = bit.bxor(h, data:byte(i))
      h = h * FNV_PRIME
    end
    return string.format("%016x", tonumber(h))
  end
end

return mod
