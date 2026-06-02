--- telescope-m1.nvim: Telescope extension for M1 script.
---
--- Pickers:
---   workspace_symbols  fuzzy-search all channels, parameters, enums (m1-lsp)
---   components         browse the Project.m1prj component hierarchy
---   lint_rules         pick an m1-lint rule to document / yank / ignore
local ok, telescope = pcall(require, "telescope")
if not ok then
  error("telescope-m1.nvim requires nvim-telescope/telescope.nvim")
end

local config = require("telescope-m1.config")

return telescope.register_extension({
  setup = function(ext_config, _)
    config.setup(ext_config)
  end,
  exports = {
    -- `:Telescope m1` with no subcommand defaults to workspace_symbols.
    m1 = require("telescope-m1.pickers.workspace_symbols"),
    workspace_symbols = require("telescope-m1.pickers.workspace_symbols"),
    components = require("telescope-m1.pickers.components"),
    lint_rules = require("telescope-m1.pickers.lint_rules"),
  },
})
