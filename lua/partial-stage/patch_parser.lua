local M = {}

-- Parse a unified diff hunk header "@@ -a,b +c,d @@" or "@@ -a +c @@"
function M.parse_hunk_header(line)
  local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
  if old_start then
    return {
      old_start = tonumber(old_start),
      old_count = tonumber(old_count),
      new_start = tonumber(new_start),
      new_count = tonumber(new_count),
    }
  end

  -- Without count (single line)
  old_start, new_start = line:match("^@@ %-(%d+) %+(%d+) @@")
  if old_start then
    return {
      old_start = tonumber(old_start),
      old_count = 1,
      new_start = tonumber(new_start),
      new_count = 1,
    }
  end

  -- Mixed: one has count, the other doesn't
  old_start, old_count, new_start = line:match("^@@ %-(%d+),(%d+) %+(%d+) @@")
  if old_start then
    return {
      old_start = tonumber(old_start),
      old_count = tonumber(old_count),
      new_start = tonumber(new_start),
      new_count = 1,
    }
  end

  old_start, new_start, new_count = line:match("^@@ %-(%d+) %+(%d+),(%d+) @@")
  if old_start then
    return {
      old_start = tonumber(old_start),
      old_count = 1,
      new_start = tonumber(new_start),
      new_count = tonumber(new_count),
    }
  end

  return nil
end

-- Build a hunk header string from parsed values
function M.make_hunk_header(header)
  return string.format("@@ -%d,%d +%d,%d @@", header.old_start, header.old_count, header.new_start, header.new_count)
end

-- Parse unified diff output into structured data
-- Returns a list of file diffs, each containing hunks
function M.parse(diff_text)
  if not diff_text or diff_text == "" then
    return {}
  end

  local lines = vim.split(diff_text, "\n", { plain = true })
  local files = {}
  local current_file = nil
  local current_hunk = nil
  local i = 1

  while i <= #lines do
    local line = lines[i]

    -- File header: "diff --git a/path b/path"
    if line:match("^diff %-%-git a/.+ b/.+") then
      local a_file, b_file = line:match("^diff %-%-git a/(.+) b/(.+)")
      current_file = {
        a_file = a_file,
        b_file = b_file,
        header_lines = { line },
        hunks = {},
      }
      table.insert(files, current_file)
      current_hunk = nil
      i = i + 1

    -- Extended headers (index, old mode, new mode, etc.)
    elseif
      current_file
      and not current_hunk
      and (
        line:match("^index ")
        or line:match("^old mode ")
        or line:match("^new mode ")
        or line:match("^new file mode ")
        or line:match("^deleted file mode ")
        or line:match("^rename from ")
        or line:match("^rename to ")
        or line:match("^similarity index ")
        or line:match("^dissimilarity index ")
        or line:match("^%-%-%- ")
        or line:match("^%+%+%+ ")
      )
    then
      table.insert(current_file.header_lines, line)
      i = i + 1

    -- Hunk header: "@@ -a,b +c,d @@"
    elseif current_file and line:match("^@@ ") then
      local header = M.parse_hunk_header(line)
      if header then
        current_hunk = {
          header = header,
          header_line = line,
          lines = {},
        }
        table.insert(current_file.hunks, current_hunk)
      end
      i = i + 1

    -- Hunk content lines (+, -, space, or \ No newline)
    elseif current_hunk and (line:match("^[+ -]") or line:match("^\\ ") or line == "") then
      -- Empty line at the end of diff is just trailing newline, skip
      if line == "" and i == #lines then
        i = i + 1
      else
        table.insert(current_hunk.lines, line)
        i = i + 1
      end
    else
      -- Unrecognized line, skip
      i = i + 1
    end
  end

  return files
end

-- Reconstruct the file header portion of a patch for a given file
function M.make_file_header(file)
  return table.concat(file.header_lines, "\n")
end

-- Reconstruct a complete patch for a single hunk
function M.make_patch(file, hunk)
  local parts = {}
  table.insert(parts, M.make_file_header(file))
  table.insert(parts, hunk.header_line)
  for _, line in ipairs(hunk.lines) do
    table.insert(parts, line)
  end
  return table.concat(parts, "\n") .. "\n"
end

-- Reconstruct a partial patch from selected lines within a hunk
-- selected_indices: list of 1-based indices into hunk.lines that are selected
-- mode: "stage" - patch is relative to the original file (for git apply --cached)
--        "discard" - patch is relative to the working tree (for git apply --reverse)
--
-- For "stage":  unselected "-" → context (exists in original), unselected "+" → omit
-- For "discard": unselected "-" → omit (not in working tree), unselected "+" → context (in working tree)
function M.make_partial_patch(file, hunk, selected_indices, mode)
  local selected_set = {}
  for _, idx in ipairs(selected_indices) do
    selected_set[idx] = true
  end

  local new_lines = {}
  local old_count = 0
  local new_count = 0

  for i, line in ipairs(hunk.lines) do
    local prefix = line:sub(1, 1)
    if prefix == " " or line:match("^\\ ") then
      -- Context line: always include
      table.insert(new_lines, line)
      if prefix == " " then
        old_count = old_count + 1
        new_count = new_count + 1
      end
    elseif prefix == "-" then
      if selected_set[i] then
        table.insert(new_lines, line)
        old_count = old_count + 1
      elseif mode == "discard" then
        -- Not in working tree: omit entirely
      else
        -- In original file: convert to context line
        table.insert(new_lines, " " .. line:sub(2))
        old_count = old_count + 1
        new_count = new_count + 1
      end
    elseif prefix == "+" then
      if selected_set[i] then
        table.insert(new_lines, line)
        new_count = new_count + 1
      elseif mode == "discard" then
        -- In working tree: convert to context line
        table.insert(new_lines, " " .. line:sub(2))
        old_count = old_count + 1
        new_count = new_count + 1
      else
        -- Not in original file: omit entirely
      end
    end
  end

  local new_header = {
    old_start = hunk.header.old_start,
    old_count = old_count,
    new_start = hunk.header.new_start,
    new_count = new_count,
  }

  local parts = {}
  table.insert(parts, M.make_file_header(file))
  table.insert(parts, M.make_hunk_header(new_header))
  for _, line in ipairs(new_lines) do
    table.insert(parts, line)
  end
  return table.concat(parts, "\n") .. "\n"
end

-- Split a hunk into smaller hunks at context-line boundaries
-- A "change group" is a contiguous block of +/- lines.
-- Groups separated by context lines become separate hunks.
function M.split_hunk(hunk)
  local groups = {}
  local current_group = nil
  local context_buffer = {}

  for _, line in ipairs(hunk.lines) do
    local prefix = line:sub(1, 1)

    if prefix == "+" or prefix == "-" then
      -- Start a new group if needed
      if not current_group then
        current_group = {
          leading_context = {},
          changes = {},
          trailing_context = {},
        }
        -- Move context_buffer to leading_context of new group
        -- (also trailing_context of previous group)
        if #groups > 0 then
          local prev = groups[#groups]
          -- Split context: first half to previous trailing, second half to current leading
          local split_at = math.ceil(#context_buffer / 2)
          for i = 1, #context_buffer do
            if i <= split_at then
              table.insert(prev.trailing_context, context_buffer[i])
            else
              table.insert(current_group.leading_context, context_buffer[i])
            end
          end
        else
          -- First group gets all context as leading
          for _, ctx in ipairs(context_buffer) do
            table.insert(current_group.leading_context, ctx)
          end
        end
        context_buffer = {}
        table.insert(groups, current_group)
      end
      table.insert(current_group.changes, line)
    elseif prefix == " " then
      if current_group then
        -- Context line after changes: end current group
        table.insert(context_buffer, line)
        current_group = nil
      else
        table.insert(context_buffer, line)
      end
    else
      -- "\ No newline" or other
      if current_group then
        table.insert(current_group.changes, line)
      end
    end
  end

  -- Handle trailing context for the last group
  if #groups > 0 and #context_buffer > 0 then
    local last = groups[#groups]
    for _, ctx in ipairs(context_buffer) do
      table.insert(last.trailing_context, ctx)
    end
  end

  -- If only one group (or none), the hunk cannot be split
  if #groups <= 1 then
    return nil
  end

  -- Build new hunks from groups
  local result = {}
  local old_offset = hunk.header.old_start
  local new_offset = hunk.header.new_start

  for _, group in ipairs(groups) do
    local lines = {}
    local old_count = 0
    local new_count = 0

    for _, l in ipairs(group.leading_context) do
      table.insert(lines, l)
      old_count = old_count + 1
      new_count = new_count + 1
    end

    for _, l in ipairs(group.changes) do
      table.insert(lines, l)
      local p = l:sub(1, 1)
      if p == "-" then
        old_count = old_count + 1
      elseif p == "+" then
        new_count = new_count + 1
      end
    end

    for _, l in ipairs(group.trailing_context) do
      table.insert(lines, l)
      old_count = old_count + 1
      new_count = new_count + 1
    end

    local new_header = {
      old_start = old_offset,
      old_count = old_count,
      new_start = new_offset,
      new_count = new_count,
    }

    table.insert(result, {
      header = new_header,
      header_line = M.make_hunk_header(new_header),
      lines = lines,
    })

    -- Advance offsets for next sub-hunk
    old_offset = old_offset + old_count
    new_offset = new_offset + new_count
  end

  return result
end

return M
