-- sed/awk output parser
-- annotates transformation output with line counts

return function(output, args)
  local tool = args[1]

  local line_count = 0
  for _ in output:gmatch("[^\n]+") do
    line_count = line_count + 1
  end

  return {
    shape = "text",
    annotations = {
      tool = tool or "sed",
      line_count = tostring(line_count),
    },
  }
end
