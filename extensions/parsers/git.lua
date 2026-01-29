-- git output parser
-- detects: log, diff, status, branch, show

return function(output, args)
  local subcmd = args[2] -- git <subcmd>
  if not subcmd then return nil end

  if subcmd == "log" then
    local commits = 0
    for _ in output:gmatch("\ncommit [0-9a-f]+") do commits = commits + 1 end
    -- first commit may not have leading newline
    if output:match("^commit [0-9a-f]+") then commits = commits + 1 end
    return {
      shape = "log",
      annotations = {
        tool = "git",
        git_subcmd = "log",
        commit_count = tostring(commits),
      },
    }

  elseif subcmd == "diff" then
    local files = {}
    local insertions, deletions = 0, 0
    for line in output:gmatch("[^\n]+") do
      local f = line:match("^diff %-%-git a/(.+) b/")
      if f then files[#files + 1] = f end
      if line:match("^%+") and not line:match("^%+%+%+") then insertions = insertions + 1 end
      if line:match("^%-") and not line:match("^%-%-%-") then deletions = deletions + 1 end
    end
    return {
      shape = "log",
      annotations = {
        tool = "git",
        git_subcmd = "diff",
        files_changed = tostring(#files),
        insertions = tostring(insertions),
        deletions = tostring(deletions),
      },
    }

  elseif subcmd == "status" then
    local modified, added, deleted, untracked = 0, 0, 0, 0
    for line in output:gmatch("[^\n]+") do
      if line:match("^%s*M") then modified = modified + 1
      elseif line:match("^%s*A") or line:match("^%s*new file") then added = added + 1
      elseif line:match("^%s*D") or line:match("^%s*deleted") then deleted = deleted + 1
      elseif line:match("^%?%?") or line:match("Untracked") then untracked = untracked + 1
      end
    end
    return {
      shape = "log",
      annotations = {
        tool = "git",
        git_subcmd = "status",
        modified = tostring(modified),
        added = tostring(added),
        deleted = tostring(deleted),
        untracked = tostring(untracked),
      },
    }

  elseif subcmd == "branch" then
    local branches = 0
    local current
    for line in output:gmatch("[^\n]+") do
      branches = branches + 1
      local cur = line:match("^%* (.+)")
      if cur then current = cur end
    end
    return {
      shape = "list",
      annotations = {
        tool = "git",
        git_subcmd = "branch",
        branch_count = tostring(branches),
        current_branch = current,
      },
    }
  end

  -- fallback for other subcommands
  return {
    shape = "text",
    annotations = {
      tool = "git",
      git_subcmd = subcmd,
    },
  }
end
