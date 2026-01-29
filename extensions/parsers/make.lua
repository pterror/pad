-- make/cargo/npm build output parser
-- counts errors and warnings

return function(output, args)
  local tool = args[1]
  local errors = 0
  local warnings = 0

  for line in output:gmatch("[^\n]+") do
    local lower = line:lower()
    if lower:match("error[:%[]") or lower:match("^error") then
      errors = errors + 1
    end
    if lower:match("warning[:%[]") or lower:match("^warning") then
      warnings = warnings + 1
    end
  end

  -- detect pass/fail
  local success = errors == 0

  return {
    shape = "log",
    annotations = {
      tool = tool or "make",
      error_count = tostring(errors),
      warning_count = tostring(warnings),
      build_success = tostring(success),
    },
  }
end
