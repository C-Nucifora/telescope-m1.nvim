--- telescope-m1: extension configuration.
---
--- Picker data comes from m1-lsp (symbols/components) and m1-lint (rules), so
--- there is little to configure today; this module keeps a single place to add
--- options and is wired to telescope's `extensions.m1` setup table.
local M = {}

---@class TelescopeM1Config

---@type TelescopeM1Config
M.options = {}

--- Merge `ext_config` (from telescope's setup) into the defaults.
---@param ext_config? table
function M.setup(ext_config)
  M.options = vim.tbl_deep_extend("force", M.options, ext_config or {})
end

return M
