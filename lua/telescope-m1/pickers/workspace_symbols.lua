--- telescope-m1: workspace symbol picker — flat fuzzy search over every
--- channel, parameter, enum and function in the loaded project (via m1-lsp).
local symbol_picker = require("telescope-m1.symbol_picker")

---@param opts? table  Standard telescope picker options.
return function(opts)
  opts = opts or {}
  symbol_picker.from_lsp(opts, {
    title = "M1 Workspace Symbols",
    query = opts.query or "",
  })
end
