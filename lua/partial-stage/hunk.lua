local git = require("partial-stage.git")
local parser = require("partial-stage.patch_parser")
local status = require("partial-stage.status")

local M = {}

-- Find the hunk and file data for the current cursor position
local function get_hunk_context()
  local node = status.get_current_node()
  if not node then
    return nil
  end

  local result = {
    node = node,
    section = node.section,
  }

  if node.type == "hunk_header" or node.type == "diff_line" then
    result.hunk = node.hunk_data
    result.file = node.file_data
  elseif node.type == "file" then
    result.file = node.file_data
  end

  return result
end

-- Stage a single hunk
function M.stage_hunk(file, hunk, on_done)
  local patch = parser.make_patch(file, hunk)
  git.apply_patch(patch, { "--cached", "--whitespace=nowarn" }, function(_, err)
    if err then
      vim.notify("Failed to stage hunk: " .. err, vim.log.levels.ERROR)
    end
    if on_done then
      on_done(err)
    end
  end)
end

-- Unstage a single hunk
function M.unstage_hunk(file, hunk, on_done)
  local patch = parser.make_patch(file, hunk)
  git.apply_patch(patch, { "--cached", "--reverse", "--whitespace=nowarn" }, function(_, err)
    if err then
      vim.notify("Failed to unstage hunk: " .. err, vim.log.levels.ERROR)
    end
    if on_done then
      on_done(err)
    end
  end)
end

-- Discard a hunk (revert working tree changes)
function M.discard_hunk(file, hunk, on_done)
  local patch = parser.make_patch(file, hunk)
  git.apply_patch(patch, { "--reverse", "--whitespace=nowarn" }, function(_, err)
    if err then
      vim.notify("Failed to discard hunk: " .. err, vim.log.levels.ERROR)
    end
    if on_done then
      on_done(err)
    end
  end)
end

-- Stage partial hunk (selected lines)
function M.stage_partial(file, hunk, selected_indices, on_done)
  local patch = parser.make_partial_patch(file, hunk, selected_indices, "stage")
  git.apply_patch(patch, { "--cached", "--whitespace=nowarn" }, function(_, err)
    if err then
      vim.notify("Failed to stage partial hunk: " .. err, vim.log.levels.ERROR)
    end
    if on_done then
      on_done(err)
    end
  end)
end

-- Unstage partial hunk (selected lines)
function M.unstage_partial(file, hunk, selected_indices, on_done)
  local patch = parser.make_partial_patch(file, hunk, selected_indices, "unstage")
  git.apply_patch(patch, { "--cached", "--reverse", "--whitespace=nowarn" }, function(_, err)
    if err then
      vim.notify("Failed to unstage partial hunk: " .. err, vim.log.levels.ERROR)
    end
    if on_done then
      on_done(err)
    end
  end)
end

-- Toggle stage/unstage for hunk under cursor (normal mode)
function M.toggle_stage()
  local ctx = get_hunk_context()
  if not ctx then
    return
  end

  if ctx.hunk and ctx.file then
    local on_done = function()
      status.refresh()
    end
    if ctx.section == "unstaged" then
      M.stage_hunk(ctx.file, ctx.hunk, on_done)
    elseif ctx.section == "staged" then
      M.unstage_hunk(ctx.file, ctx.hunk, on_done)
    end
  elseif ctx.file and not ctx.hunk then
    -- On a file node: stage/unstage all hunks for this file
    local on_done = function()
      status.refresh()
    end
    if ctx.section == "unstaged" then
      git.stage_file(ctx.file.b_file, on_done)
    elseif ctx.section == "staged" then
      git.reset_file(ctx.file.b_file, on_done)
    end
  end
end

-- Get selected line indices within a hunk from visual selection
local function get_visual_hunk_lines()
  -- Get visual selection range
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local st = status.get_state()
  if not st.outline then
    return nil
  end

  -- Find the hunk that contains the selection
  local hunk_data, file_data, section
  local selected_indices = {}

  for line = start_line, end_line do
    local node = st.outline:node_at_line(line)
    if node and node.type == "diff_line" then
      if not hunk_data then
        hunk_data = node.hunk_data
        file_data = node.file_data
        section = node.section
      end
      -- Only include lines from the same hunk
      if node.hunk_data == hunk_data then
        -- Find the index of this line in hunk.lines
        for i, hline in ipairs(hunk_data.lines) do
          if hline == node.text then
            -- Check this hasn't been added already
            local already = false
            for _, idx in ipairs(selected_indices) do
              if idx == i then
                already = true
                break
              end
            end
            if not already then
              table.insert(selected_indices, i)
              break
            end
          end
        end
      end
    end
  end

  if hunk_data and #selected_indices > 0 then
    return {
      hunk = hunk_data,
      file = file_data,
      section = section,
      selected_indices = selected_indices,
    }
  end
  return nil
end

-- Toggle stage/unstage for visually selected lines
function M.toggle_stage_visual()
  local sel = get_visual_hunk_lines()
  if not sel then
    -- Fallback to normal mode behavior
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    M.toggle_stage()
    return
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  local on_done = function()
    status.refresh()
  end

  if sel.section == "unstaged" then
    M.stage_partial(sel.file, sel.hunk, sel.selected_indices, on_done)
  elseif sel.section == "staged" then
    M.unstage_partial(sel.file, sel.hunk, sel.selected_indices, on_done)
  end
end

-- Discard hunk under cursor (normal mode, unstaged only)
function M.discard()
  local ctx = get_hunk_context()
  if not ctx or ctx.section ~= "unstaged" then
    vim.notify("Discard only works in the Unstaged section", vim.log.levels.WARN)
    return
  end

  if ctx.hunk and ctx.file then
    vim.ui.select({ "Yes", "No" }, { prompt = "Discard this hunk?" }, function(choice)
      if choice == "Yes" then
        M.discard_hunk(ctx.file, ctx.hunk, function()
          status.refresh()
        end)
      end
    end)
  end
end

-- Discard visually selected lines (unstaged only)
function M.discard_visual()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  M.discard()
end

-- Jump to file at cursor position
function M.jump_to_file()
  local ctx = get_hunk_context()
  if not ctx or not ctx.file then
    return
  end

  local filepath = ctx.file.b_file
  local line = 1

  if ctx.hunk then
    line = ctx.hunk.header.new_start
  end

  -- Close status window and open the file
  status.close()
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

-- Split hunk under cursor into smaller hunks
function M.split()
  local ctx = get_hunk_context()
  if not ctx or not ctx.hunk then
    vim.notify("No hunk under cursor to split", vim.log.levels.WARN)
    return
  end

  local sub_hunks = parser.split_hunk(ctx.hunk)
  if not sub_hunks then
    vim.notify("Hunk cannot be split further", vim.log.levels.INFO)
    return
  end

  -- Replace the original hunk with sub-hunks in file_data
  local file = ctx.file
  for i, hunk in ipairs(file.hunks) do
    if hunk == ctx.hunk then
      table.remove(file.hunks, i)
      for j, sub in ipairs(sub_hunks) do
        table.insert(file.hunks, i + j - 1, sub)
      end
      break
    end
  end

  -- Refresh the display
  status.refresh()
end

return M
