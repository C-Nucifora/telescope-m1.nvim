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
---   <C-r>  rename the component             (m1-project via nvim-m1, #18)
---   <C-d>  delete the component             (m1-project via nvim-m1, #18)
---   <C-q>  set the entry's physical quantity (m1-project via nvim-m1, #45)
---   <C-e>  edit another attribute — pick from validation / format / decimal
---          places / display range / add tag / remove tag (m1-project via
---          nvim-m1, #45)
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local symbol_picker = require("telescope-m1.symbol_picker")
local m1_lsp = require("telescope-m1.lsp")

--- The extra component editors reachable through `<C-e>`, in menu order. Each
--- maps a human-facing label to the matching `nvim-m1.project` function (same
--- `(cfg, component)` signature as the directly-bound editors). Surfacing them
--- behind one vim.ui.select keeps parity with the attributes the detail card
--- already shows (qty/tags/validation/format/range) without exhausting `<C-*>`.
local EXTRA_EDITS = {
  { label = "Quantity", fn = "set_quantity" },
  { label = "Validation", fn = "set_validation" },
  { label = "Format", fn = "set_format" },
  { label = "Decimal places", fn = "set_dps" },
  { label = "Display range", fn = "set_display_range" },
  { label = "Add tag", fn = "add_tag" },
  { label = "Remove tag", fn = "remove_tag" },
}

--- Run one of nvim-m1's project editors with the selected component, closing
--- the picker first (the editor opens its own prompts). Degrades to a notify
--- (not an error) when nvim-m1 is absent or too old to expose `fn_name`, so a
--- newer telescope-m1 stays usable against an older nvim-m1.
---@param fn_name "set_security"|"set_type"|"set_unit"|"rename_component"|"delete_component"|"set_quantity"|"set_validation"|"set_format"|"set_dps"|"set_display_range"|"add_tag"|"remove_tag"
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
    local project = require("nvim-m1.project")
    if type(project[fn_name]) ~= "function" then
      vim.notify(
        "telescope-m1: this edit needs a newer nvim-m1 (missing " .. fn_name .. ")",
        vim.log.levels.WARN
      )
      return
    end
    actions.close(bufnr)
    project[fn_name](nvim_m1.config, entry.value.name)
  end
end

--- <C-e>: pick one of the extra component attributes (validation/format/dps/…)
--- and dispatch the chosen `nvim-m1.project` editor for the selected entry. The
--- attribute is chosen *before* the picker closes (so the entry is still the
--- selection), then `project_edit` runs the editor.
local function select_edit(bufnr)
  if not action_state.get_selected_entry() then
    return
  end
  local labels = {}
  for _, e in ipairs(EXTRA_EDITS) do
    labels[#labels + 1] = e.label
  end
  vim.ui.select(labels, { prompt = "Edit component attribute" }, function(choice)
    if not choice then
      return
    end
    for _, e in ipairs(EXTRA_EDITS) do
      if e.label == choice then
        project_edit(e.fn)(bufnr)
        return
      end
    end
  end)
end

--- <C-f>: open the backing script of a Function/Method entry (#8). For those
--- kinds the LSP symbol's location *is* the .m1scr file.
local function goto_backing_script(bufnr)
  local entry = action_state.get_selected_entry()
  if not entry then
    return
  end
  local kind = entry.value and entry.value.kind_label
  if kind ~= "Function" and kind ~= "Method" then
    vim.notify(
      "telescope-m1: not a script-backed entry (" .. (kind or "?") .. ")",
      vim.log.levels.INFO
    )
    return
  end
  if not entry.filename or entry.filename == "" then
    vim.notify("telescope-m1: no backing file for this entry", vim.log.levels.WARN)
    return
  end
  actions.close(bufnr)
  vim.cmd.edit(entry.filename)
  if entry.lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, 0 })
  end
end

--- The picker is callable — `require("telescope-m1.pickers.components")(opts)`
--- still works — but is a table so `goto_backing_script` can be exposed
--- (underscore-prefixed) for the unit tests to invoke the real source.
--- `Picker` is forward-declared so `__call` captures it as an upvalue (the
--- local is not in scope inside its own initialiser).
local Picker
Picker = setmetatable({}, {
  __call = function(_, opts)
    return Picker.open(opts)
  end,
})

-- Private-by-convention handles for the unit tests.
Picker._goto_backing_script = goto_backing_script
Picker._project_edit = project_edit
Picker._select_edit = select_edit
Picker._EXTRA_EDITS = EXTRA_EDITS

---@param opts? table
function Picker.open(opts)
  opts = opts or {}
  symbol_picker.from_lsp(opts, {
    title = "M1 Components",
    query = "",
    hierarchy = true,
    transform = m1_lsp.build_hierarchy,
    -- Detail card instead of raw Project.m1prj XML for component rows (#23).
    previewer = require("telescope-m1.component_preview").previewer(opts),
    attach_mappings = function(_, map)
      map({ "i", "n" }, "<C-f>", goto_backing_script)
      map({ "i", "n" }, "<C-s>", project_edit("set_security"))
      map({ "i", "n" }, "<C-t>", project_edit("set_type"))
      map({ "i", "n" }, "<C-u>", project_edit("set_unit"))
      map({ "i", "n" }, "<C-r>", project_edit("rename_component"))
      map({ "i", "n" }, "<C-d>", project_edit("delete_component"))
      map({ "i", "n" }, "<C-q>", project_edit("set_quantity"))
      map({ "i", "n" }, "<C-e>", select_edit)
      return true -- keep the default <CR> navigate
    end,
  })
end

return Picker
