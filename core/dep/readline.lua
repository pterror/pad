-- readline wrapper using LuaJIT FFI
-- Falls back to basic io.read if readline not available

local ffi = require("ffi")
local mod = {}

-- Try to load readline
local ok, readline_lib = pcall(function()
  ffi.cdef[[
    char *readline(const char *prompt);
    void add_history(const char *line);
    int read_history(const char *filename);
    int write_history(const char *filename);
    void free(void *ptr);
  ]]
  return ffi.load("readline")
end)

if ok then
  -- Readline available
  mod.available = true

  function mod.readline(prompt)
    local cstr = readline_lib.readline(prompt)
    if cstr == nil then
      return nil
    end
    local str = ffi.string(cstr)
    ffi.C.free(cstr)
    return str
  end

  function mod.add_history(line)
    if line and #line > 0 then
      readline_lib.add_history(line)
    end
  end

  function mod.read_history(filename)
    readline_lib.read_history(filename)
  end

  function mod.write_history(filename)
    readline_lib.write_history(filename)
  end
else
  -- Fallback to basic io
  mod.available = false

  function mod.readline(prompt)
    io.stderr:write(prompt)
    return io.stdin:read("*l")
  end

  function mod.add_history(line)
    -- no-op without readline
  end

  function mod.read_history(filename)
    -- no-op without readline
  end

  function mod.write_history(filename)
    -- no-op without readline
  end
end

return mod
