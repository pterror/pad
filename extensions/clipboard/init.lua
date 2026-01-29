--[[
pad clipboard extension

Captures clipboard content with source = "clipboard".
Platform-specific: tries wl-paste, xclip, xsel, pbpaste in order.
]]

local mod = {}

local clipboard_cmds = {
  { cmd = "wl-paste --no-newline 2>/dev/null", name = "wl-paste" },
  { cmd = "xclip -selection clipboard -o 2>/dev/null", name = "xclip" },
  { cmd = "xsel --clipboard --output 2>/dev/null", name = "xsel" },
  { cmd = "pbpaste 2>/dev/null", name = "pbpaste" },
}

function mod.detect()
  for _, entry in ipairs(clipboard_cmds) do
    local handle = io.popen("command -v " .. entry.name .. " >/dev/null 2>&1 && echo yes")
    if handle then
      local result = handle:read("*l")
      handle:close()
      if result == "yes" then
        return entry
      end
    end
  end
  return nil
end

function mod.read()
  local entry = mod.detect()
  if not entry then
    return nil, "no clipboard tool found (tried wl-paste, xclip, xsel, pbpaste)"
  end
  local handle = io.popen(entry.cmd)
  if not handle then
    return nil, "failed to run " .. entry.name
  end
  local content = handle:read("*a")
  handle:close()
  if not content or #content == 0 then
    return nil, "clipboard is empty"
  end
  return content, entry.name
end

return mod
