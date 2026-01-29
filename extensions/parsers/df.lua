-- df/du output parser
-- counts filesystems or entries, detects disk usage

return function(output, args)
  local tool = args[1]

  if tool == "du" then
    local entries = 0
    for _ in output:gmatch("[^\n]+") do
      entries = entries + 1
    end
    return {
      shape = "table",
      annotations = {
        tool = "du",
        entry_count = tostring(entries),
      },
    }
  end

  -- df: skip header, count filesystems
  local filesystems = 0
  local first = true
  for line in output:gmatch("[^\n]+") do
    if first then
      first = false
    else
      if #line > 0 then filesystems = filesystems + 1 end
    end
  end

  return {
    shape = "table",
    annotations = {
      tool = "df",
      filesystem_count = tostring(filesystems),
    },
  }
end
