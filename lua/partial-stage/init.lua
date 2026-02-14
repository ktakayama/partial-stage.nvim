local config = require("partial-stage.config")

local M = {}

function M.setup(opts)
  config.setup(opts)
end

function M.open()
  require("partial-stage.status").open()
end

function M.close()
  require("partial-stage.status").close()
end

function M.toggle()
  require("partial-stage.status").toggle()
end

return M
