--[[
pad validate - invariant enforcement

Pure validators. No side effects, no database access.
These define what is structurally valid in pad.
]]

local mod = {}

function mod.source(source)
  if not source then
    error("pad: source is required (invariant: every object needs provenance)")
  end
  if type(source) ~= "string" or #source == 0 then
    error("pad: source must be a non-empty string, got: " .. tostring(source))
  end
  return true
end

function mod.tier(size, force_full, tiers, budgets)
  if size > budgets.max_payload_bytes then
    return "sketch", "truncated_by_budget:max_payload_bytes"
  end
  if size > tiers.sketch_threshold and not force_full then
    return "sketch", nil
  end
  return "full", nil
end

function mod.edge(from_id, to_id, relation, event_id)
  if not from_id then error("pad: edge requires from_id") end
  if not to_id then error("pad: edge requires to_id") end
  if not relation or type(relation) ~= "string" or #relation == 0 then
    error("pad: edge requires a non-empty relation string")
  end
  if not event_id then
    error("pad: edge requires event_id (invariant: every edge needs provenance)")
  end
  return true
end

function mod.annotation(opts)
  if not opts.object_id and not opts.event_id then
    error("pad: annotation requires object_id or event_id")
  end
  if not opts.key then error("pad: annotation requires key") end
  if not opts.value then error("pad: annotation requires value") end
  return true
end

return mod
