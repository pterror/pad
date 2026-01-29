-- ripgrep output parser
-- format: file:line:col:match or file:line:match

return function(output, args)
  local files = {}
  local match_count = 0

  for line in output:gmatch("[^\n]+") do
    local file = line:match("^(.+):%d+:")
    if file then
      match_count = match_count + 1
      files[file] = true
    end
  end

  local file_count = 0
  for _ in pairs(files) do file_count = file_count + 1 end

  -- extract pattern from args (first non-flag arg after rg)
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
      tool = "rg",
      match_count = tostring(match_count),
      file_count = tostring(file_count),
      pattern = pattern,
    },
  }
end
