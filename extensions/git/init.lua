--[[
pad git extension

Captures git log, diff, and status output with source = "git:<subcmd>".
Operates on the current working directory's git repo.
]]

local mod = {}

local function run(cmd)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then return nil end
  local output = handle:read("*a")
  handle:close()
  if not output or #output == 0 then return nil end
  return output
end

function mod.is_repo()
  local output = run("git rev-parse --is-inside-work-tree 2>/dev/null")
  return output and output:match("true") ~= nil
end

function mod.log(n)
  n = n or 20
  return run("git log --oneline -" .. tostring(n))
end

function mod.log_full(n)
  n = n or 10
  return run("git log -" .. tostring(n))
end

function mod.diff(ref)
  if ref then
    return run("git diff " .. ref)
  end
  return run("git diff")
end

function mod.status()
  return run("git status --short")
end

function mod.show(ref)
  ref = ref or "HEAD"
  return run("git show " .. ref)
end

return mod
