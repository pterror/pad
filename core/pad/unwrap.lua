--[[
pad unwrap - recursive command prefix stripping

Pure function. Peels off wrappers (nix run, sudo, time, strace, etc.)
to find the real command being executed. Provenance is a core concern.
]]

local mod = {}

-- each matcher: (args) -> (real_args, wrapper_name) | nil
local matchers = {}

matchers[1] = function(args)
  -- nix run nixpkgs#foo -- <real command>
  if args[1] ~= "nix" or args[2] ~= "run" then return nil end
  for i = 3, #args do
    if args[i] == "--" then
      local real = {}
      for j = i + 1, #args do real[#real + 1] = args[j] end
      return real, "nix run"
    end
  end
end

matchers[2] = function(args)
  -- nix-shell -p foo --run "command"
  if args[1] ~= "nix-shell" then return nil end
  for i = 2, #args do
    if args[i] == "--run" or args[i] == "--command" then
      if args[i + 1] then
        return { args[i + 1] }, "nix-shell"
      end
    end
  end
end

matchers[3] = function(args)
  -- nix develop ... --command <real command>
  if args[1] ~= "nix" or args[2] ~= "develop" then return nil end
  for i = 3, #args do
    if args[i] == "--command" or args[i] == "-c" then
      local real = {}
      for j = i + 1, #args do real[#real + 1] = args[j] end
      return real, "nix develop"
    end
  end
end

matchers[4] = function(args)
  -- simple prefixes: time, sudo, doas, command, exec, nice
  local prefixes = {
    time = true, sudo = true, doas = true,
    ["command"] = true, exec = true,
  }
  if not prefixes[args[1]] then return nil end
  local real = {}
  for i = 2, #args do real[#real + 1] = args[i] end
  return real, args[1]
end

matchers[5] = function(args)
  -- nice -n N <real command>
  if args[1] ~= "nice" then return nil end
  local i = 2
  if args[i] and args[i]:match("^%-n") then
    if args[i] == "-n" then i = i + 2 else i = i + 1 end
  end
  local real = {}
  for j = i, #args do real[#real + 1] = args[j] end
  return real, "nice"
end

matchers[6] = function(args)
  -- env [-flags] VAR=val... <real command>
  if args[1] ~= "env" then return nil end
  local i = 2
  while i <= #args and args[i]:match("^%-") do i = i + 1 end
  while i <= #args and args[i]:match("^%w+=") do i = i + 1 end
  local real = {}
  for j = i, #args do real[#real + 1] = args[j] end
  return real, "env"
end

matchers[7] = function(args)
  -- strace [-flags [-values]] <real command>
  if args[1] ~= "strace" then return nil end
  local i = 2
  local valued = { o = true, e = true, p = true, s = true, P = true, u = true, E = true }
  while i <= #args and args[i]:match("^%-") do
    local flag = args[i]:match("^%-(%a)$")
    if flag and valued[flag] then i = i + 1 end
    i = i + 1
  end
  local real = {}
  for j = i, #args do real[#real + 1] = args[j] end
  return real, "strace"
end

matchers[8] = function(args)
  -- ltrace, same shape as strace
  if args[1] ~= "ltrace" then return nil end
  local i = 2
  while i <= #args and args[i]:match("^%-") do i = i + 1 end
  local real = {}
  for j = i, #args do real[#real + 1] = args[j] end
  return real, "ltrace"
end

matchers[9] = function(args)
  -- timeout DURATION <real command>
  if args[1] ~= "timeout" then return nil end
  local i = 2
  while i <= #args and args[i]:match("^%-") do i = i + 1 end
  i = i + 1 -- skip duration
  local real = {}
  for j = i, #args do real[#real + 1] = args[j] end
  return real, "timeout"
end

matchers[10] = function(args)
  -- watch -n N <real command>
  if args[1] ~= "watch" then return nil end
  local i = 2
  while i <= #args and args[i]:match("^%-") do
    if args[i] == "-n" or args[i] == "-d" then i = i + 1 end
    i = i + 1
  end
  local real = {}
  for j = i, #args do real[#real + 1] = args[j] end
  return real, "watch"
end

-- peel one wrapper layer
local function unwrap_one(args)
  if #args == 0 then return nil end
  for _, matcher in ipairs(matchers) do
    local real, name = matcher(args)
    if real and #real > 0 then return real, name end
  end
end

-- recursively unwrap all layers
function mod.unwrap(args)
  local wrappers = {}
  local current = args
  for _ = 1, 10 do
    local real, name = unwrap_one(current)
    if not real then break end
    wrappers[#wrappers + 1] = name
    current = real
  end
  return current, wrappers
end

-- extract base command name (strip path)
function mod.base_command(args)
  if #args == 0 then return nil end
  return args[1]:match("([^/]+)$")
end

return mod
