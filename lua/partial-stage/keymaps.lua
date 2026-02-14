local config = require("partial-stage.config")

local M = {}

function M.setup(bufnr)
  local keymaps = config.values.keymaps
  local opts = { noremap = true, silent = true, buffer = bufnr }

  if keymaps.toggle_fold then
    vim.keymap.set("n", keymaps.toggle_fold, function()
      require("partial-stage.status").toggle_fold()
    end, opts)
  end

  if keymaps.close then
    vim.keymap.set("n", keymaps.close, function()
      require("partial-stage.status").close()
    end, opts)
  end

  if keymaps.toggle_stage then
    vim.keymap.set("n", keymaps.toggle_stage, function()
      require("partial-stage.hunk").toggle_stage()
    end, opts)
    vim.keymap.set("v", keymaps.toggle_stage, function()
      require("partial-stage.hunk").toggle_stage_visual()
    end, opts)
  end

  if keymaps.discard then
    vim.keymap.set("n", keymaps.discard, function()
      require("partial-stage.hunk").discard()
    end, opts)
    vim.keymap.set("v", keymaps.discard, function()
      require("partial-stage.hunk").discard_visual()
    end, opts)
  end

  if keymaps.jump then
    vim.keymap.set("n", keymaps.jump, function()
      require("partial-stage.hunk").jump_to_file()
    end, opts)
  end

  if keymaps.split_hunk then
    vim.keymap.set("n", keymaps.split_hunk, function()
      require("partial-stage.hunk").split()
    end, opts)
  end
end

return M
