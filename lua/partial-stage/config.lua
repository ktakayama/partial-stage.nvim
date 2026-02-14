local M = {}

local defaults = {
  window = {
    position = "topleft vsplit",
    width = 60,
  },
  signs = {
    collapsed = ">",
    expanded = "v",
  },
  keymaps = {
    toggle_stage = "dp",
    discard = "x",
    toggle_fold = "<Tab>",
    jump = "<CR>",
    split_hunk = "gs",
    close = "q",
  },
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
