-- curl/wget output parser
-- extracts HTTP status, URL, content type from verbose/header output

return function(output, args)
  local tool = args[1]

  -- extract URL from args
  local url
  for i = 2, #args do
    if args[i]:match("^https?://") then
      url = args[i]
      break
    end
  end

  -- detect HTTP status from headers (curl -i, curl -v, wget -S)
  local status_code = output:match("HTTP/%d[%.%d]* (%d+)")
  local content_type = output:match("[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)")

  -- detect if output looks like JSON, HTML, or plain
  local shape = "text"
  local trimmed = output:match("^%s*(.-)%s*$") or ""
  if trimmed:match("^{") or trimmed:match("^%[") then
    shape = "object"
  elseif trimmed:match("^<!") or trimmed:match("^<html") then
    shape = "text"
  end

  return {
    shape = shape,
    annotations = {
      tool = tool or "curl",
      url = url,
      http_status = status_code,
      content_type = content_type,
    },
  }
end
