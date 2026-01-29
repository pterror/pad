-- tree output parser
-- last line: "N directories, M files"

return function(output, args)
  local dirs, files
  local summary = output:match("(%d+ directories?, %d+ files?)%s*$")
  if summary then
    dirs = summary:match("^(%d+) director")
    files = summary:match(", (%d+) file")
  end

  return {
    shape = "list",
    annotations = {
      tool = "tree",
      dir_count = dirs,
      file_count = files,
    },
  }
end
