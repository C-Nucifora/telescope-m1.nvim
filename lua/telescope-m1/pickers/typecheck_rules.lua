--- telescope-m1: m1-typecheck T-code picker.
---
--- Browse the m1-typecheck rule catalogue (code + name).
---   <CR>  open the "How it works" documentation in a browser
---   <C-y> yank the T-code (e.g. "T031") to the clipboard
---
--- Deliberately NO ignore action (unlike the lint_rules picker). m1-lint reads a
--- per-tool `.m1lint.toml` this plugin can safely line-edit, but typecheck's
--- select/ignore lives in the unified `m1-tools.toml` `[diagnostics]` table —
--- an LSP-owned file shared by VS Code and Neovim, with nested tables
--- (`[diagnostics.severity]`) a line-oriented merge can't touch cleanly. Per
--- AGENTS.md, project/config mutations belong to nvim-m1 → m1-project, not this
--- presentation layer, so we surface the catalogue and leave the write out.
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")
local typecheck_rules = require("telescope-m1.typecheck_rules")

local function make_entry(displayer)
  return function(rule)
    return {
      value = rule,
      ordinal = rule.code .. " " .. rule.name,
      display = function()
        return displayer({
          { rule.code, "TelescopeResultsNumber" },
          { rule.name, "TelescopeResultsIdentifier" },
        })
      end,
    }
  end
end

--- A static previewer: the catalogue carries no per-rule rationale (there is no
--- `m1-typecheck --explain <TCODE>` — its `--explain` explains a channel, not a
--- rule), so show the code + name and point at the docs. One buffer per T-code.
local function previewer()
  return previewers.new_buffer_previewer({
    title = "M1 Typecheck Rule",
    get_buffer_by_name = function(_, entry)
      return entry.value and entry.value.code or tostring(entry.ordinal)
    end,
    define_preview = function(self, entry)
      local rule = entry.value or {}
      local lines = {
        (rule.code or "?") .. "  " .. (rule.name or ""),
        "",
        "m1-typecheck static check.",
        "Docs: " .. typecheck_rules.docs_url_for(rule),
      }
      local bufnr = self.state.bufnr
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.bo[bufnr].modifiable = false
      end
    end,
  })
end

--- Yank a T-code to the `+` (system) and `"` (unnamed) registers (<C-y>).
--- Extracted so the unit test drives the real handler instead of a copy.
---@param entry table?  the selected Telescope entry (`entry.value.code`)
local function yank_code(entry)
  if entry then
    vim.fn.setreg("+", entry.value.code)
    vim.fn.setreg('"', entry.value.code)
    vim.notify("telescope-m1: yanked " .. entry.value.code)
  end
end

--- The picker is callable — `require("telescope-m1.pickers.typecheck_rules")(opts)`
--- still works — but is a table so the private helpers above can be exposed
--- (underscore-prefixed) for the unit tests to invoke the real source.
local Picker
Picker = setmetatable({}, {
  __call = function(_, opts)
    return Picker.open(opts)
  end,
})

-- Private-by-convention handles for the unit tests.
Picker._make_entry = make_entry
Picker._yank_code = yank_code

---@param opts? table
function Picker.open(opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 5 },
      { remaining = true },
    },
  })

  pickers
    .new(opts, {
      prompt_title = "M1 Typecheck Rules",
      finder = finders.new_table({
        results = typecheck_rules.all(),
        entry_maker = make_entry(displayer),
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewer(),
      attach_mappings = function(prompt_bufnr, map)
        -- <CR>: open the documentation section.
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          local url = entry and typecheck_rules.docs_url_for(entry.value)
            or typecheck_rules.docs_url
          local ok = pcall(function()
            vim.ui.open(url)
          end)
          if not ok then
            vim.notify("telescope-m1: docs at " .. url, vim.log.levels.INFO)
          end
        end)
        -- <C-y>: yank the code.
        map({ "i", "n" }, "<C-y>", function()
          yank_code(action_state.get_selected_entry())
        end)
        return true
      end,
    })
    :find()
end

return Picker
