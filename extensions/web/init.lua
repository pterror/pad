--[[
pad web UI - HTTP route handler

Serves a single-page web UI and JSON API on the daemon's HTTP port.
Uses table router for path-based dispatch with wildcard :id capture.
]]

local json = require("dep.lunajson")
local table_router = require("dep.http.router.table")

local mod = {}

-- resolve static file directory from this module's source path
local source = debug.getinfo(1, "S").source
local dir = source:match("@(.*/)" ) or "./"

-- cached static files
local index_cache

local function send_json(res, data, status)
  res.status = status or 200
  res.headers["content-type"] = "application/json"
  res.body = json.encode(data)
end

local function parse_body(req)
  if not req.body or #req.body == 0 then return nil end
  local ok, data = pcall(json.decode, req.body)
  if not ok then return nil end
  return data
end

-- wrap handler in pcall for error safety
local function handler(fn)
  return function(req, res)
    local ok, err = pcall(fn, req, res)
    if not ok then
      send_json(res, { ok = false, error = tostring(err) }, 500)
    end
    return true
  end
end

function mod.router(pad)
  return table_router.router({
    -- GET / → serve index.html
    [""] = handler(function(req, res)
      if not index_cache then
        local f = io.open(dir .. "static/index.html", "r")
        if not f then
          res.status = 500
          res.headers["content-type"] = "text/plain"
          res.body = "index.html not found"
          return
        end
        index_cache = f:read("*a")
        f:close()
      end
      res.headers["content-type"] = "text/html"
      res.body = index_cache
    end),

    api = {
      objects = {
        -- GET /api/objects(?search=&shape=&limit=)
        [""] = handler(function(req, res)
          local limit = tonumber(req.params.limit) or 50
          local results = {}

          if req.params.search and #req.params.search > 0 then
            local term = "%" .. req.params.search .. "%"
            for id, hash, shape, sketch, size, coldness, created_at in pad.query([[
              SELECT id, hash, shape, sketch, size, coldness, created_at FROM objects
              WHERE sketch LIKE ? OR payload LIKE ?
              ORDER BY coldness ASC, created_at DESC LIMIT ?;
            ]], term, term, limit) do
              results[#results+1] = { id=id, hash=hash, shape=shape, sketch=sketch, size=size, coldness=coldness, created_at=created_at }
            end
          elseif req.params.shape and #req.params.shape > 0 then
            for id, hash, shape, sketch, size, coldness, created_at in pad.query([[
              SELECT id, hash, shape, sketch, size, coldness, created_at FROM objects
              WHERE shape = ?
              ORDER BY created_at DESC LIMIT ?;
            ]], req.params.shape, limit) do
              results[#results+1] = { id=id, hash=hash, shape=shape, sketch=sketch, size=size, coldness=coldness, created_at=created_at }
            end
          else
            for id, hash, shape, sketch, size, coldness, created_at in pad.query([[
              SELECT id, hash, shape, sketch, size, coldness, created_at FROM objects
              ORDER BY created_at DESC LIMIT ?;
            ]], limit) do
              results[#results+1] = { id=id, hash=hash, shape=shape, sketch=sketch, size=size, coldness=coldness, created_at=created_at }
            end
          end

          send_json(res, { ok = true, results = results })
        end),

        -- /api/objects/:id (wildcard capture)
        [1] = {
          -- GET /api/objects/:id
          [""] = handler(function(req, res)
            local raw_id = req.globs[1]
            local id = tonumber(raw_id)
            if not id then
              id = pad.find_by_hash_prefix(raw_id)
            end
            if not id then
              send_json(res, { ok = false, error = "not found" }, 404)
              return
            end
            local obj = pad.get_object(id)
            if not obj then
              send_json(res, { ok = false, error = "not found" }, 404)
              return
            end
            -- annotations
            local annotations = {}
            for ann_id, key, value, created_at in pad.query(
              "SELECT id, key, value, created_at FROM annotations WHERE object_id = ? ORDER BY created_at DESC;", id
            ) do
              annotations[#annotations+1] = { id=ann_id, key=key, value=value, created_at=created_at }
            end
            -- edges from this object
            local edges_from = {}
            for edge_id, to_id, relation, created_at in pad.query(
              "SELECT id, to_id, relation, created_at FROM edges WHERE from_id = ?;", id
            ) do
              edges_from[#edges_from+1] = { id=edge_id, to_id=to_id, relation=relation, created_at=created_at }
            end
            -- edges to this object
            local edges_to = {}
            for edge_id, from_id, relation, created_at in pad.query(
              "SELECT id, from_id, relation, created_at FROM edges WHERE to_id = ?;", id
            ) do
              edges_to[#edges_to+1] = { id=edge_id, from_id=from_id, relation=relation, created_at=created_at }
            end

            send_json(res, {
              ok = true,
              object = obj,
              annotations = annotations,
              edges_from = edges_from,
              edges_to = edges_to,
            })
          end),

          -- POST/DELETE /api/objects/:id/tag
          tag = handler(function(req, res)
            local id = tonumber(req.globs[1])
            if not id then
              send_json(res, { ok = false, error = "invalid id" }, 400)
              return
            end
            local body = parse_body(req)
            if not body or not body.tag then
              send_json(res, { ok = false, error = "tag required" }, 400)
              return
            end
            if req.method == "POST" then
              pad.annotate({ object_id = id, key = "tag", value = body.tag })
              send_json(res, { ok = true })
            elseif req.method == "DELETE" then
              pad.remove_annotation({ object_id = id, key = "tag", value = body.tag })
              send_json(res, { ok = true })
            else
              send_json(res, { ok = false, error = "method not allowed" }, 405)
            end
          end),

          -- POST /api/objects/:id/note
          note = handler(function(req, res)
            if req.method ~= "POST" then
              send_json(res, { ok = false, error = "method not allowed" }, 405)
              return
            end
            local target_id = tonumber(req.globs[1])
            if not target_id then
              send_json(res, { ok = false, error = "invalid id" }, 400)
              return
            end
            local body = parse_body(req)
            if not body or not body.text or #body.text == 0 then
              send_json(res, { ok = false, error = "text required" }, 400)
              return
            end
            local note_id, hash = pad.ingest(body.text, { source = "web" })
            local event_id = pad.create_event({ source = "web" })
            pad.link(note_id, target_id, "references", event_id)
            send_json(res, { ok = true, id = note_id, hash = hash })
          end),
        },
      },

      -- GET /api/events(?limit=)
      events = {
        [""] = handler(function(req, res)
          local limit = tonumber(req.params.limit) or 50
          local results = {}
          for id, created_at, cwd, command, source in pad.query([[
            SELECT id, created_at, cwd, command, source FROM events
            ORDER BY created_at DESC LIMIT ?;
          ]], limit) do
            results[#results+1] = { id=id, created_at=created_at, cwd=cwd, command=command, source=source }
          end
          send_json(res, { ok = true, results = results })
        end),
      },

      -- GET /api/stats
      stats = {
        [""] = handler(function(req, res)
          local function count(sql)
            local iter = pad.query(sql)
            return iter()
          end
          send_json(res, {
            ok = true,
            objects = count("SELECT COUNT(*) FROM objects;"),
            events = count("SELECT COUNT(*) FROM events;"),
            edges = count("SELECT COUNT(*) FROM edges;"),
            annotations = count("SELECT COUNT(*) FROM annotations;"),
            total_size = count("SELECT COALESCE(SUM(size), 0) FROM objects;"),
          })
        end),
      },

      -- GET /api/urgent
      urgent = {
        [""] = handler(function(req, res)
          local results = {}
          for id, hash, shape, sketch, size, tag in pad.query([[
            SELECT o.id, o.hash, o.shape, o.sketch, o.size, a.value
            FROM objects o
            JOIN annotations a ON a.object_id = o.id
            WHERE a.key = 'tag' AND a.value IN ('urgent', 'action')
            ORDER BY o.created_at DESC;
          ]]) do
            results[#results+1] = { id=id, hash=hash, shape=shape, sketch=sketch, size=size, tag=tag }
          end
          send_json(res, { ok = true, results = results })
        end),
      },

      -- POST /api/ingest
      ingest = {
        [""] = handler(function(req, res)
          if req.method ~= "POST" then
            send_json(res, { ok = false, error = "method not allowed" }, 405)
            return
          end
          local body = parse_body(req)
          if not body or not body.content or #body.content == 0 then
            send_json(res, { ok = false, error = "content required" }, 400)
            return
          end
          local source = body.source or "web"
          local id, hash = pad.ingest(body.content, { source = source, metadata = body.metadata })
          send_json(res, { ok = true, id = id, hash = hash })
        end),
      },
    },
  })
end

return mod
