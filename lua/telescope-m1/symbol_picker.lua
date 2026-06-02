--- telescope-m1: shared symbol picker.
---
--- Both the workspace-symbols and components pickers present m1-lsp
--- `workspace/symbol` results; they differ only in layout (flat fuzzy list vs.
--- indented hierarchy). This module holds the shared finder/entry plumbing so
--- neither picker copies it.
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local entry_display = require("telescope.pickers.entry_display")
local m1_lsp = require("telescope-m1.lsp")

local M = {}

--- @param hierarchy boolean  Indent by `entry.depth` (component browser) or not.
local function make_entry(displayer, hierarchy)
  return function(sym)
    return {
      value = sym,
      ordinal = sym.name .. " " .. (sym.kind_label or ""),
      display = function(e)
        local s = e.value
        local indent = hierarchy and string.rep("  ", s.depth or 0) or ""
        return displayer({
          { m1_lsp.kind_icon(s.kind), "TelescopeResultsComment" },
          { indent .. s.name, "TelescopeResultsIdentifier" },
          { s.kind_label or "", "TelescopeResultsComment" },
        })
      end,
      filename = sym.filename,
      lnum = sym.lnum,
      col = sym.col,
    }
  end
end

--- Open a picker over `entries` (a list from `lsp.symbol_to_entry`).
---@param opts table
---@param spec { title: string, entries: table[], hierarchy?: boolean }
function M.open(opts, spec)
  local displayer = entry_display.create({
    separator = " ",
    items = { { width = 2 }, { remaining = true }, { remaining = true } },
  })

  pickers
    .new(opts, {
      prompt_title = spec.title,
      finder = finders.new_table({
        results = spec.entries,
        entry_maker = make_entry(displayer, spec.hierarchy),
      }),
      sorter = conf.generic_sorter(opts),
      previewer = conf.qflist_previewer(opts),
    })
    :find()
end

--- Fetch workspace symbols and open a picker, handling the empty/error cases.
---@param opts table
---@param spec { title: string, query?: string, hierarchy?: boolean, transform?: fun(entries: table[]): table[] }
function M.from_lsp(opts, spec)
  m1_lsp.workspace_symbols(spec.query or "", function(entries, err)
    if err then
      vim.schedule(function()
        vim.notify("telescope-m1: " .. err, vim.log.levels.WARN)
      end)
      return
    end
    if vim.tbl_isempty(entries) then
      vim.schedule(function()
        vim.notify("telescope-m1: no symbols", vim.log.levels.INFO)
      end)
      return
    end
    if spec.transform then
      entries = spec.transform(entries)
    end
    vim.schedule(function()
      M.open(
        opts,
        { title = spec.title, entries = entries, hierarchy = spec.hierarchy }
      )
    end)
  end)
end

return M
