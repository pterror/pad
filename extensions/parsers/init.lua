--[[
pad parsers - output format plugins

Each parser is a function: (output, args) -> result | nil
Result: { shape = "...", annotations = { key = "value", ... } }

Parsers are extensions: they add structured metadata to objects
but never modify core behavior. Core detects shapes; parsers
add format-specific detail.
]]

local mod = {}
local registry = {}

function mod.register(name, fn)
  registry[name] = fn
end

function mod.get(name)
  return registry[name]
end

function mod.parse(name, output, args)
  local fn = registry[name]
  if not fn then return nil end
  return fn(output, args)
end

function mod.list()
  local names = {}
  for name in pairs(registry) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- register built-in parsers
mod.register("rg", require("parsers.rg"))
mod.register("ls", require("parsers.ls"))
mod.register("grep", require("parsers.grep"))
mod.register("jq", require("parsers.jq"))
mod.register("tree", require("parsers.tree"))
mod.register("find", require("parsers.find"))
mod.register("git", require("parsers.git"))
mod.register("docker", require("parsers.docker"))
mod.register("curl", require("parsers.curl"))
mod.register("wget", require("parsers.curl"))
mod.register("make", require("parsers.make"))
mod.register("cargo", require("parsers.make"))
mod.register("npm", require("parsers.make"))
mod.register("ps", require("parsers.ps"))
mod.register("top", require("parsers.ps"))
mod.register("df", require("parsers.df"))
mod.register("du", require("parsers.df"))
mod.register("sed", require("parsers.sed"))
mod.register("awk", require("parsers.sed"))

return mod
