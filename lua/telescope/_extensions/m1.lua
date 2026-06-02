--- telescope-m1.nvim: Telescope extension for M1 script.
local telescope     = require("telescope")
local pickers       = require("telescope.pickers")
local finders       = require("telescope.finders")
local conf          = require("telescope.config").values
local actions       = require("telescope.actions")
local action_state  = require("telescope.actions.state")

local M = {}

--- Fuzzy-search all workspace symbols (channels, parameters, enums) via LSP.
function M.workspace_symbols(opts)
  opts = opts or {}
  -- TODO: call vim.lsp.buf.workspace_symbol and stream results into a picker
  vim.notify("telescope-m1: workspace_symbols not yet implemented", vim.log.levels.WARN)
end

--- Browse the Project.m1prj component hierarchy.
function M.components(opts)
  opts = opts or {}
  -- TODO: read LoadedProject component tree from m1-lsp custom request
  vim.notify("telescope-m1: components not yet implemented", vim.log.levels.WARN)
end

--- Pick an m1-lint rule to toggle or jump to documentation.
function M.lint_rules(opts)
  opts = opts or {}
  -- TODO: enumerate rules from m1-lint registry via m1-lsp custom request
  vim.notify("telescope-m1: lint_rules not yet implemented", vim.log.levels.WARN)
end

return telescope.register_extension({
  exports = {
    workspace_symbols = M.workspace_symbols,
    components        = M.components,
    lint_rules        = M.lint_rules,
  },
})
