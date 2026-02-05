-- tree output parser
-- last line: "N directories, M files" or "N directory, M file"

return function(output, args)
  local dirs, files
  -- match "N director(y|ies), M file(s)" at end of output
  dirs = output:match("(%d+) director[yies]+,%s*%d+ files?%s*$")
  files = output:match("%d+ director[yies]+,%s*(%d+) files?%s*$")

  return {
    shape = "list",
    annotations = {
      tool = "tree",
      dir_count = dirs,
      file_count = files,
    },
  }
end
