-- find output parser
-- one path per line

return function(output, args)
  local dirs = 0
  local files = 0

  for line in output:gmatch("[^\n]+") do
    if line:match("/$") then
      dirs = dirs + 1
    else
      files = files + 1
    end
  end

  -- check for -type flag
  local type_filter
  for i = 1, #args do
    if args[i] == "-type" and args[i + 1] then
      type_filter = args[i + 1]
      break
    end
  end

  return {
    shape = "list",
    annotations = {
      tool = "find",
      entry_count = tostring(dirs + files),
      file_count = tostring(files),
      dir_count = tostring(dirs),
      type_filter = type_filter,
    },
  }
end
