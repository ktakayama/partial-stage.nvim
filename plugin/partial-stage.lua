if vim.g.loaded_partial_stage then
  return
end
vim.g.loaded_partial_stage = true

vim.api.nvim_create_user_command("PartialStage", function()
  require("partial-stage").open()
end, {})

vim.api.nvim_create_user_command("PartialStageClose", function()
  require("partial-stage").close()
end, {})
