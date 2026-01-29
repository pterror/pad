-- grep output parser
-- format: file:line or file:line:match (with -n/-H)

return function(output, args)
  local files = {}
  local match_count = 0

  for line in output:gmatch("[^\n]+") do
    match_count = match_count + 1
    local file = line:match("^(.+):%d+:")
    if file then files[file] = true end
  end

  local file_count = 0
  for _ in pairs(files) do file_count = file_count + 1 end

  -- extract pattern (first non-flag arg after grep)
  local pattern
  for i = 2, #args do
    if not args[i]:match("^%-") then
      pattern = args[i]
      break
    end
  end

  return {
    shape = "log",
    annotations = {
      tool = "grep",
      match_count = tostring(match_count),
      file_count = tostring(file_count),
      pattern = pattern,
    },
  }
end
