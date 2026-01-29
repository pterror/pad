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

function mod.budget_objects(count, budgets)
  if count >= budgets.max_objects_per_event then
    error("pad: budget exceeded: max_objects_per_event (" .. budgets.max_objects_per_event .. ")")
  end
  return true
end

function mod.budget_edges(count, budgets)
  if count >= budgets.max_edges_per_event then
    error("pad: budget exceeded: max_edges_per_event (" .. budgets.max_edges_per_event .. ")")
  end
  return true
end

-- known edge relation types
mod.known_relations = {
  supersedes = true,
  derived_from = true,
  references = true,
  reply_to = true,
  sketch_of = true,
}

function mod.watch_path(path)
  if not path then
    error("pad: watch path is required")
  end
  if type(path) ~= "string" or #path == 0 then
    error("pad: watch path must be a non-empty string, got: " .. tostring(path))
  end
  return true
end

function mod.relation(relation)
  if not relation or type(relation) ~= "string" or #relation == 0 then
    error("pad: relation must be a non-empty string")
  end
  if not mod.known_relations[relation] then
    error("pad: unknown relation '" .. relation .. "' (known: supersedes, derived_from, references, reply_to, sketch_of)")
  end
  return true
end

return mod
