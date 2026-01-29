-- ps/top output parser
-- counts processes, detects format

return function(output, args)
  local tool = args[1]

  -- count lines (skip header)
  local entries = 0
  local first = true
  for line in output:gmatch("[^\n]+") do
    if first then
      first = false
    else
      if #line > 0 then entries = entries + 1 end
    end
  end

  return {
    shape = "table",
    annotations = {
      tool = tool or "ps",
      process_count = tostring(entries),
    },
  }
end
