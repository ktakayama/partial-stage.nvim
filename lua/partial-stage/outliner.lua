local config = require("partial-stage.config")

local M = {}

local ns = vim.api.nvim_create_namespace("partial_stage")

-- Create a new outliner instance bound to a buffer
function M.new(bufnr)
  local self = {
    bufnr = bufnr,
    root = { children = {}, depth = -1 },
    -- Map from buffer line number (0-indexed) to node
    line_to_node = {},
  }
  return setmetatable(self, { __index = M })
end

-- Add a child node to a parent
function M.add_node(parent, node)
  node.depth = (parent.depth or -1) + 1
  node.children = node.children or {}
  node.collapsed = node.collapsed or false
  table.insert(parent.children, node)
  return node
end

-- Render the tree into the buffer
function M:render()
  local lines = {}
  local highlights = {}
  self.line_to_node = {}

  local function walk(node)
    if node.depth < 0 then
      -- Root node, just walk children
      for _, child in ipairs(node.children) do
        walk(child)
      end
      return
    end

    local lineno = #lines
    node.lineno = lineno

    -- Build display text
    local indent = string.rep("  ", node.depth)
    local text

    if node.type == "section" then
      text = node.text
    elseif node.type == "file" then
      local sign = node.collapsed and config.values.signs.collapsed or config.values.signs.expanded
      if #node.children > 0 then
        text = indent .. sign .. " " .. node.text
      else
        text = indent .. "  " .. node.text
      end
    elseif node.type == "hunk_header" then
      text = indent .. node.text
    elseif node.type == "diff_line" then
      text = indent .. node.text
    elseif node.type == "blank" then
      text = ""
    else
      text = indent .. (node.text or "")
    end

    table.insert(lines, text)
    self.line_to_node[lineno] = node

    -- Collect highlight info
    if node.hl_group then
      table.insert(highlights, { lineno, node.hl_group, 0, -1 })
    end

    -- Render children if not collapsed
    if not node.collapsed then
      for _, child in ipairs(node.children) do
        walk(child)
      end
    end
  end

  walk(self.root)

  -- Write lines to buffer
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(self.bufnr, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(self.bufnr, ns, hl[2], hl[1], hl[3], hl[4])
  end

  vim.bo[self.bufnr].modifiable = false
end

-- Find the node at a given buffer line (1-indexed, as vim reports)
function M:node_at_line(line)
  return self.line_to_node[line - 1]
end

-- Walk up from a node to find ancestor of a given type
function M:find_ancestor(start_line, target_type)
  -- Search line_to_node for the node, then walk tree upward
  local node = self:node_at_line(start_line)
  if not node then
    return nil
  end

  -- We need to find the parent by walking the tree
  local function find_parent(root, target)
    for _, child in ipairs(root.children or {}) do
      if child == target then
        return root
      end
      local found = find_parent(child, target)
      if found then
        return found
      end
    end
    return nil
  end

  local current = node
  while current do
    if current.type == target_type then
      return current
    end
    current = find_parent(self.root, current)
  end
  return nil
end

-- Toggle collapsed state of node at line
function M:toggle_fold(line)
  local node = self:node_at_line(line)
  if node and #(node.children or {}) > 0 then
    node.collapsed = not node.collapsed
    self:render()
    return true
  end
  return false
end

-- Clear the tree
function M:clear()
  self.root = { children = {}, depth = -1 }
  self.line_to_node = {}
end

return M
