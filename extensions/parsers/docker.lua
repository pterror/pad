-- docker output parser
-- detects: ps, images, container ls

return function(output, args)
  local subcmd = args[2] -- docker <subcmd>
  if not subcmd then return nil end

  -- count rows (skip header line)
  local entries = 0
  local first = true
  for line in output:gmatch("[^\n]+") do
    if first then
      first = false
    else
      if #line > 0 then entries = entries + 1 end
    end
  end

  local kind
  if subcmd == "ps" or subcmd == "container" then
    kind = "container"
  elseif subcmd == "images" or subcmd == "image" then
    kind = "image"
  elseif subcmd == "volume" then
    kind = "volume"
  elseif subcmd == "network" then
    kind = "network"
  end

  return {
    shape = "table",
    annotations = {
      tool = "docker",
      docker_subcmd = subcmd,
      entry_count = tostring(entries),
      resource_type = kind,
    },
  }
end
