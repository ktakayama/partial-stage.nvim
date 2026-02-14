local config = require("partial-stage.config")
local git = require("partial-stage.git")
local parser = require("partial-stage.patch_parser")
local outliner = require("partial-stage.outliner")

local M = {}

local state = {
  bufnr = nil,
  winid = nil,
  outline = nil,
  -- Parsed diff data
  unstaged_files = {},
  staged_files = {},
  -- Raw diff text (for patch reconstruction)
  unstaged_diff = "",
  staged_diff = "",
}

local buf_name = "partial-stage://status"

-- Check if the status buffer is open and valid
local function is_open()
  return state.bufnr
    and vim.api.nvim_buf_is_valid(state.bufnr)
    and state.winid
    and vim.api.nvim_win_is_valid(state.winid)
end

-- Create or find the status buffer
local function get_or_create_buf()
  -- Check if buffer already exists
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == buf_name then
      state.bufnr = bufnr
      return bufnr
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, buf_name)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "partial-stage"
  state.bufnr = bufnr
  return bufnr
end

-- Open the status window
local function open_window(bufnr)
  local cfg = config.values.window
  vim.cmd(cfg.position)
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_win_set_width(winid, cfg.width)

  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true

  state.winid = winid
  return winid
end

-- Build the tree from parsed diff data
local function build_tree(outline, head_info, unstaged_files, staged_files)
  outline:clear()

  -- Head section
  local branch = head_info.branch or "HEAD"
  local msg = head_info.commit_msg or ""
  local head_text = "Head: " .. branch
  if msg ~= "" then
    head_text = head_text .. "  " .. msg
  end
  outliner.add_node(outline.root, {
    type = "section",
    text = head_text,
    hl_group = "PartialStageBranch",
  })

  -- Blank line
  outliner.add_node(outline.root, { type = "blank", text = "" })

  -- Unstaged section
  local unstaged_section = outliner.add_node(outline.root, {
    type = "section",
    text = string.format("Unstaged (%d)", #unstaged_files),
    hl_group = "PartialStageSection",
    section = "unstaged",
  })

  for _, file in ipairs(unstaged_files) do
    local file_node = outliner.add_node(unstaged_section, {
      type = "file",
      text = file.b_file,
      hl_group = "PartialStageFile",
      file_data = file,
      section = "unstaged",
      collapsed = false,
    })

    for _, hunk in ipairs(file.hunks) do
      local hunk_node = outliner.add_node(file_node, {
        type = "hunk_header",
        text = hunk.header_line,
        hl_group = "PartialStageHunkHeader",
        hunk_data = hunk,
        file_data = file,
        section = "unstaged",
      })

      for line_idx, line in ipairs(hunk.lines) do
        local hl = nil
        if line:match("^%+") then
          hl = "DiffAdd"
        elseif line:match("^%-") then
          hl = "DiffDelete"
        end
        outliner.add_node(hunk_node, {
          type = "diff_line",
          text = line,
          hl_group = hl,
          section = "unstaged",
          hunk_data = hunk,
          file_data = file,
          hunk_line_index = line_idx,
        })
      end
    end
  end

  -- Blank line
  outliner.add_node(outline.root, { type = "blank", text = "" })

  -- Staged section
  local staged_section = outliner.add_node(outline.root, {
    type = "section",
    text = string.format("Staged (%d)", #staged_files),
    hl_group = "PartialStageSection",
    section = "staged",
  })

  for _, file in ipairs(staged_files) do
    local file_node = outliner.add_node(staged_section, {
      type = "file",
      text = file.b_file,
      hl_group = "PartialStageFile",
      file_data = file,
      section = "staged",
      collapsed = true,
    })

    for _, hunk in ipairs(file.hunks) do
      local hunk_node = outliner.add_node(file_node, {
        type = "hunk_header",
        text = hunk.header_line,
        hl_group = "PartialStageHunkHeader",
        hunk_data = hunk,
        file_data = file,
        section = "staged",
      })

      for line_idx, line in ipairs(hunk.lines) do
        local hl = nil
        if line:match("^%+") then
          hl = "DiffAdd"
        elseif line:match("^%-") then
          hl = "DiffDelete"
        end
        outliner.add_node(hunk_node, {
          type = "diff_line",
          text = line,
          hl_group = hl,
          section = "staged",
          hunk_data = hunk,
          file_data = file,
          hunk_line_index = line_idx,
        })
      end
    end
  end
end

-- Setup highlight groups
local function setup_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "PartialStageBranch", { link = "Title", default = true })
  hl(0, "PartialStageSection", { link = "Label", default = true })
  hl(0, "PartialStageFile", { link = "Directory", default = true })
  hl(0, "PartialStageHunkHeader", { link = "Function", default = true })
end

-- Refresh the buffer content
function M.refresh()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local pending = 3
  local head_info = {}
  local unstaged_diff = ""
  local staged_diff = ""

  local function on_all_done()
    pending = pending - 1
    if pending > 0 then
      return
    end

    state.unstaged_diff = unstaged_diff
    state.staged_diff = staged_diff
    state.unstaged_files = parser.parse(unstaged_diff)
    state.staged_files = parser.parse(staged_diff)

    if not state.outline then
      state.outline = outliner.new(state.bufnr)
    end

    -- Save cursor position
    local cursor = nil
    if state.winid and vim.api.nvim_win_is_valid(state.winid) then
      cursor = vim.api.nvim_win_get_cursor(state.winid)
    end

    build_tree(state.outline, head_info, state.unstaged_files, state.staged_files)
    state.outline:render()

    -- Restore cursor position
    if cursor and state.winid and vim.api.nvim_win_is_valid(state.winid) then
      local line_count = vim.api.nvim_buf_line_count(state.bufnr)
      if cursor[1] > line_count then
        cursor[1] = line_count
      end
      vim.api.nvim_win_set_cursor(state.winid, cursor)
    end
  end

  git.get_head_info(function(info, _)
    head_info = info or {}
    on_all_done()
  end)

  git.get_diff(false, function(out, _)
    unstaged_diff = out or ""
    on_all_done()
  end)

  git.get_diff(true, function(out, _)
    staged_diff = out or ""
    on_all_done()
  end)
end

-- Get the node at the current cursor position
function M.get_current_node()
  if not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  return state.outline:node_at_line(cursor[1]), cursor[1]
end

-- Get state (for use by hunk.lua and keybindings)
function M.get_state()
  return state
end

-- Open the status buffer
function M.open()
  -- Check if we're in a git repository
  local result = vim.system({ "git", "rev-parse", "--git-dir" }, { text = true }):wait()
  if result.code ~= 0 then
    vim.notify("Not a git repository", vim.log.levels.ERROR)
    return
  end

  if is_open() then
    vim.api.nvim_set_current_win(state.winid)
    M.refresh()
    return
  end

  setup_highlights()
  local bufnr = get_or_create_buf()
  open_window(bufnr)
  state.outline = outliner.new(bufnr)

  -- Setup keybindings
  require("partial-stage.keymaps").setup(bufnr)

  -- Cleanup when buffer is wiped
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      state.bufnr = nil
      state.winid = nil
      state.outline = nil
    end,
  })

  M.refresh()
end

-- Close the status buffer
function M.close()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
end

-- Toggle the status buffer
function M.toggle()
  if is_open() then
    M.close()
  else
    M.open()
  end
end

-- Toggle fold at the current cursor line
function M.toggle_fold()
  if not state.outline then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  state.outline:toggle_fold(cursor[1])
end

return M
