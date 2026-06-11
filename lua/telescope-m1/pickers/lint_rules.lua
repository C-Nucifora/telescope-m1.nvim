--- telescope-m1: m1-lint rule picker.
---
--- <CR>  open the rule's documentation in a browser
--- <C-y> yank the rule code (e.g. "L004") to the clipboard
--- <C-i> append the code to the project's .m1lint.toml `ignore` list
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local rules = require("telescope-m1.rules")
local ignore = require("telescope-m1.ignore")

local function make_entry(displayer)
  return function(rule)
    return {
      value = rule,
      ordinal = rule.code .. " " .. rule.name,
      display = function()
        return displayer({
          { rule.code, "TelescopeResultsNumber" },
          { rule.name, "TelescopeResultsIdentifier" },
          {
            rules.severity_label(rule.severity),
            rules.severity_hl(rule.severity),
          },
          { rule.fixable and "fix" or "", "TelescopeResultsComment" },
          { rule.summary, "TelescopeResultsComment" },
        })
      end,
    }
  end
end

--- Add a rule code to the nearest .m1lint.toml `ignore` list (creating the file
--- if necessary), merging into an existing single-line `ignore` array rather
--- than appending a duplicate key. Best-effort, line-oriented to avoid a TOML
--- dependency; genuinely-complex cases (multi-line arrays) fall back to a
--- warn-and-append so the file is never corrupted.
local function ignore_in_config(code)
  local dir = vim.fn.getcwd()
  local buf = vim.api.nvim_buf_get_name(0)
  if buf ~= "" then
    dir = vim.fs.dirname(buf)
  end
  local found =
    vim.fs.find(".m1lint.toml", { upward = true, path = dir, type = "file" })
  local path = found[1] or (vim.fn.getcwd() .. "/.m1lint.toml")

  local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  local new_lines, status = ignore.merge_ignore(lines, code)

  if status == "already_ignored" then
    vim.notify(
      "telescope-m1: " .. code .. " already ignored in " .. path,
      vim.log.levels.INFO
    )
    return
  end

  vim.fn.writefile(new_lines, path)

  if status == "fallback" then
    vim.notify(
      "telescope-m1: "
        .. path
        .. " has an `ignore` key this tool can't safely edit (multi-line array); "
        .. 'appended a second `ignore = ["'
        .. code
        .. '"]` — please merge it by hand to avoid a duplicate key.',
      vim.log.levels.WARN
    )
  else
    vim.notify("telescope-m1: added " .. code .. " to ignore in " .. path)
  end
end

---@param opts? table
return function(opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 5 },
      { width = 24 },
      { width = 5 },
      { width = 3 },
      { remaining = true },
    },
  })

  pickers
    .new(opts, {
      prompt_title = "M1 Lint Rules",
      finder = finders.new_table({
        results = rules.all(),
        entry_maker = make_entry(displayer),
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        -- <CR>: open documentation.
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local ok = pcall(function()
            vim.ui.open(rules.docs_url)
          end)
          if not ok then
            vim.notify("telescope-m1: docs at " .. rules.docs_url, vim.log.levels.INFO)
          end
        end)
        -- <C-y>: yank the code.
        map({ "i", "n" }, "<C-y>", function()
          local entry = action_state.get_selected_entry()
          if entry then
            vim.fn.setreg("+", entry.value.code)
            vim.fn.setreg('"', entry.value.code)
            vim.notify("telescope-m1: yanked " .. entry.value.code)
          end
        end)
        -- <C-i>: ignore in .m1lint.toml.
        map({ "i", "n" }, "<C-i>", function(pbuf)
          local entry = action_state.get_selected_entry()
          if entry then
            actions.close(pbuf)
            ignore_in_config(entry.value.code)
          end
        end)
        return true
      end,
    })
    :find()
end
