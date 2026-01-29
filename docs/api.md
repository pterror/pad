# pad HTTP API

JSON API served by the daemon on port 7778. All responses include `Access-Control-Allow-Origin: *`.

## Endpoints

### GET /

Returns `index.html` when the web extension is loaded, or JSON stats otherwise.

### GET /status

Database stats (always available, even without the web extension).

```json
{"ok":true,"objects":42,"events":58,"edges":3,"annotations":12,"total_size":8192}
```

### GET /api/stats

Same as `/status`.

### GET /api/objects

List objects. Query parameters:

| Param    | Default | Description                        |
|----------|---------|------------------------------------|
| `search` |         | Search sketch and payload content  |
| `shape`  |         | Filter by shape (text, list, log, table, object, url, path) |
| `limit`  | 50      | Max results                        |

```
GET /api/objects
GET /api/objects?search=hello
GET /api/objects?shape=list&limit=10
```

Response:

```json
{
  "ok": true,
  "results": [
    {
      "id": 1,
      "hash": "a1b2c3d4e5f6g7h8",
      "shape": "text",
      "sketch": "{\"preview\":\"hello world\",\"size\":11,\"lines\":1}",
      "size": 11,
      "coldness": 0.0,
      "created_at": 1706500000
    }
  ]
}
```

### GET /api/objects/:id

Get a single object with its annotations and edges. `:id` can be a numeric ID or a hash prefix.

```
GET /api/objects/1
GET /api/objects/a1b2c3
```

Response:

```json
{
  "ok": true,
  "object": {
    "id": 1,
    "hash": "a1b2c3d4e5f6g7h8",
    "event_id": 1,
    "tier": "full",
    "shape": "text",
    "sketch": "{...}",
    "payload": "hello world",
    "size": 11,
    "coldness": 0.0,
    "last_accessed_at": 1706500000,
    "access_count": 3,
    "created_at": 1706500000
  },
  "annotations": [
    {"id": 1, "key": "tag", "value": "todo", "created_at": 1706500000}
  ],
  "edges_from": [
    {"id": 1, "to_id": 2, "relation": "references", "created_at": 1706500000}
  ],
  "edges_to": [
    {"id": 2, "from_id": 3, "relation": "sketch_of", "created_at": 1706500000}
  ]
}
```

### POST /api/objects/:id/tag

Add a tag annotation to an object.

```
POST /api/objects/1/tag
Content-Type: application/json

{"tag": "todo"}
```

### DELETE /api/objects/:id/tag

Remove a tag annotation from an object.

```
DELETE /api/objects/1/tag
Content-Type: application/json

{"tag": "todo"}
```

### POST /api/objects/:id/note

Create a note linked to an object via a `references` edge.

```
POST /api/objects/1/note
Content-Type: application/json

{"text": "remember to follow up on this"}
```

Response:

```json
{"ok": true, "id": 5, "hash": "f8e7d6c5b4a39281"}
```

### GET /api/events

Recent events (provenance records).

| Param   | Default | Description |
|---------|---------|-------------|
| `limit` | 50      | Max results |

Response:

```json
{
  "ok": true,
  "results": [
    {
      "id": 1,
      "created_at": 1706500000,
      "cwd": "/home/user/project",
      "command": "rg foo",
      "source": "exec"
    }
  ]
}
```

### GET /api/urgent

Objects tagged `urgent` or `action`.

Response:

```json
{
  "ok": true,
  "results": [
    {
      "id": 3,
      "hash": "...",
      "shape": "text",
      "sketch": "{...}",
      "size": 42,
      "tag": "urgent"
    }
  ]
}
```

### POST /api/ingest

Ingest new content.

```
POST /api/ingest
Content-Type: application/json

{"content": "data to store", "source": "web", "metadata": {"key": "value"}}
```

`source` defaults to `"web"`. `metadata` is optional.

Response:

```json
{"ok": true, "id": 7, "hash": "1234567890abcdef"}
```

## Errors

All errors return:

```json
{"ok": false, "error": "description of what went wrong"}
```

Status codes: 400 (bad request), 404 (not found), 405 (method not allowed), 500 (server error).

## WebSocket

Connect to `ws://localhost:7778`. Messages use the same JSON dispatch protocol as the unix socket IPC:

```json
{"action": "stats"}
{"action": "search", "term": "hello"}
{"action": "ingest", "content": "data", "source": "ws"}
{"action": "show", "id": "1"}
```

See `pad/dispatch.lua` for the full list of actions.
