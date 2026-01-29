-- ls output parser
-- detects long format (-l) vs short, counts entries

return function(output, args)
  local is_long = false
  for _, a in ipairs(args) do
    if a:match("l") and a:match("^%-") then is_long = true end
  end

  local entries = 0
  for line in output:gmatch("[^\n]+") do
    if not line:match("^total ") then
      entries = entries + 1
    end
  end

  return {
    shape = is_long and "table" or "list",
    annotations = {
      tool = "ls",
      entry_count = tostring(entries),
    },
  }
end
