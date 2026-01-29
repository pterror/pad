-- jq output parser
-- output is already processed JSON

return function(output, args)
  local trimmed = output:match("^%s*(.-)%s*$")
  local shape = "text"
  if trimmed:match("^%[") then shape = "list"
  elseif trimmed:match("^{") then shape = "object"
  end

  -- extract filter (first non-flag arg after jq)
  local filter
  for i = 2, #args do
    if not args[i]:match("^%-") then
      filter = args[i]
      break
    end
  end

  return {
    shape = shape,
    annotations = {
      tool = "jq",
      filter = filter,
    },
  }
end
