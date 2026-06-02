--- telescope-m1: Project component browser.
---
--- The project's component tree (groups, channels, parameters, functions, …) is
--- exactly m1-lsp's symbol table, which it builds from Project.m1prj. So rather
--- than re-parse the .m1prj here, this picker presents the same
--- `workspace/symbol` data as an indented hierarchy ordered by dotted path —
--- staying in lock-step with the toolchain's own view of the project.
local symbol_picker = require("telescope-m1.symbol_picker")
local m1_lsp = require("telescope-m1.lsp")

---@param opts? table
return function(opts)
  opts = opts or {}
  symbol_picker.from_lsp(opts, {
    title = "M1 Components",
    query = "",
    hierarchy = true,
    transform = m1_lsp.build_hierarchy,
  })
end
