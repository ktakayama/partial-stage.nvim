local M = {}

-- Parse a unified diff hunk header "@@ -a,b +c,d @@" or "@@ -a +c @@"
function M.parse_hunk_header(line)
  local old_start, old_count, new_start, new_count =
    line:match("^@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
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
  old_start, old_count, new_start =
    line:match("^@@ %-(%d+),(%d+) %+(%d+) @@")
  if old_start then
    return {
      old_start = tonumber(old_start),
      old_count = tonumber(old_count),
      new_start = tonumber(new_start),
      new_count = 1,
    }
  end

  old_start, new_start, new_count =
    line:match("^@@ %-(%d+) %+(%d+),(%d+) @@")
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
  return string.format("@@ -%d,%d +%d,%d @@",
    header.old_start, header.old_count,
    header.new_start, header.new_count)
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
    elseif current_file and not current_hunk and (
      line:match("^index ") or
      line:match("^old mode ") or
      line:match("^new mode ") or
      line:match("^new file mode ") or
      line:match("^deleted file mode ") or
      line:match("^rename from ") or
      line:match("^rename to ") or
      line:match("^similarity index ") or
      line:match("^dissimilarity index ") or
      line:match("^%-%-%- ") or
      line:match("^%+%+%+ ")
    ) then
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
    elseif current_hunk and (
      line:match("^[+ -]") or
      line:match("^\\ ") or
      line == ""
    ) then
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
-- mode: "stage" or "unstage"
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
      else
        -- Convert to context line
        table.insert(new_lines, " " .. line:sub(2))
        old_count = old_count + 1
        new_count = new_count + 1
      end
    elseif prefix == "+" then
      if selected_set[i] then
        table.insert(new_lines, line)
        new_count = new_count + 1
      else
        -- Simply omit the line
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

return M
