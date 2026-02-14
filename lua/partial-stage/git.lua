local M = {}

-- Run a git command synchronously and return stdout as string
local function git_sync(args, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ "git" }, args)
  local result = vim.system(cmd, {
    cwd = opts.cwd,
    stdin = opts.stdin,
    text = true,
  }):wait()

  if result.code ~= 0 and not opts.ignore_error then
    return nil, (result.stderr or "unknown git error")
  end
  return result.stdout or "", nil
end

-- Run a git command asynchronously, call on_done(stdout, err) when finished
local function git_async(args, opts, on_done)
  opts = opts or {}
  local cmd = vim.list_extend({ "git" }, args)
  vim.system(cmd, {
    cwd = opts.cwd,
    stdin = opts.stdin,
    text = true,
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 and not opts.ignore_error then
        on_done(nil, result.stderr or "unknown git error")
      else
        on_done(result.stdout or "", nil)
      end
    end)
  end)
end

-- Get git status --porcelain output
function M.get_status(on_done)
  git_async({ "status", "--porcelain" }, {}, on_done)
end

-- Get diff output (cached = staged diff)
function M.get_diff(cached, on_done)
  local args = { "diff" }
  if cached then
    table.insert(args, "--cached")
  end
  git_async(args, {}, on_done)
end

-- Get current branch and last commit message
function M.get_head_info(on_done)
  local info = {}
  local pending = 2

  local function check_done()
    pending = pending - 1
    if pending == 0 then
      on_done(info, nil)
    end
  end

  git_async({ "rev-parse", "--abbrev-ref", "HEAD" }, {}, function(out, err)
    if out then
      info.branch = vim.trim(out)
    else
      info.branch = "HEAD"
    end
    check_done()
  end)

  git_async({ "log", "-1", "--format=%s" }, { ignore_error = true }, function(out, _)
    if out then
      info.commit_msg = vim.trim(out)
    else
      info.commit_msg = ""
    end
    check_done()
  end)
end

-- Apply a patch via git apply with stdin
function M.apply_patch(patch, args, on_done)
  args = args or {}
  local cmd_args = vim.list_extend({ "apply" }, args)
  git_async(cmd_args, { stdin = patch }, on_done)
end

-- Stage a file
function M.stage_file(path, on_done)
  git_async({ "add", "--", path }, {}, on_done)
end

-- Unstage a file (git reset)
function M.reset_file(path, on_done)
  git_async({ "reset", "--", path }, {}, on_done)
end

-- Synchronous versions for use in tests or simple operations
M.sync = {}

function M.sync.get_diff(cached)
  local args = { "diff" }
  if cached then
    table.insert(args, "--cached")
  end
  return git_sync(args)
end

function M.sync.apply_patch(patch, args)
  args = args or {}
  local cmd_args = vim.list_extend({ "apply" }, args)
  return git_sync(cmd_args, { stdin = patch })
end

return M
