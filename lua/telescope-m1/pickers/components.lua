--- telescope-m1: Project component browser.
---
--- The project's component tree (groups, channels, parameters, functions, …) is
--- exactly m1-lsp's symbol table, which it builds from Project.m1prj. So rather
--- than re-parse the .m1prj here, this picker presents the same
--- `workspace/symbol` data as an indented hierarchy ordered by dotted path —
--- staying in lock-step with the toolchain's own view of the project.
---
--- Mappings (besides the default `<CR>` navigate):
---   <C-f>  jump to the backing .m1scr of a Function/Method entry (#8)
---   <C-s>  set the entry's security level   (m1-project via nvim-m1, #9)
---   <C-t>  set the entry's storage type     (m1-project via nvim-m1, #9)
---   <C-u>  set the entry's display unit     (m1-project via nvim-m1, #9)
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local symbol_picker = require("telescope-m1.symbol_picker")
local m1_lsp = require("telescope-m1.lsp")

--- Run one of nvim-m1's project editors with the selected component, closing
--- the picker first (the editor opens its own prompts).
---@param fn_name "set_security"|"set_type"|"set_unit"
local function project_edit(fn_name)
  return function(bufnr)
    local entry = action_state.get_selected_entry()
    if not entry then
      return
    end
    local ok, nvim_m1 = pcall(require, "nvim-m1")
    if not ok then
      vim.notify("telescope-m1: project edits need nvim-m1", vim.log.levels.WARN)
      return
    end
    actions.close(bufnr)
    require("nvim-m1.project")[fn_name](nvim_m1.config, entry.value.name)
  end
end

--- <C-f>: open the backing script of a Function/Method entry (#8). For those
--- kinds the LSP symbol's location *is* the .m1scr file.
local function goto_backing_script(bufnr)
  local entry = action_state.get_selected_entry()
  if not entry then
    return
  end
  local kind = entry.value.kind_label
  if kind ~= "Function" and kind ~= "Method" then
    vim.notify(
      "telescope-m1: not a script-backed entry (" .. (kind or "?") .. ")",
      vim.log.levels.INFO
    )
    return
  end
  actions.close(bufnr)
  vim.cmd.edit(entry.filename)
  if entry.lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, 0 })
  end
end

---@param opts? table
return function(opts)
  opts = opts or {}
  symbol_picker.from_lsp(opts, {
    title = "M1 Components",
    query = "",
    hierarchy = true,
    transform = m1_lsp.build_hierarchy,
    attach_mappings = function(_, map)
      map({ "i", "n" }, "<C-f>", goto_backing_script)
      map({ "i", "n" }, "<C-s>", project_edit("set_security"))
      map({ "i", "n" }, "<C-t>", project_edit("set_type"))
      map({ "i", "n" }, "<C-u>", project_edit("set_unit"))
      return true -- keep the default <CR> navigate
    end,
  })
end
