--- telescope-m1: execution-rate browser (#10).
---
--- Lists the project's `On <N>Hz` clocks (via `m1-project list-rates` through
--- nvim-m1's binary resolution). On a rate:
---   <CR>   browse the scripts scheduled at that rate (m1-lsp `rate:` facet)
---   <C-a>  assign a script to this rate (prompts via nvim-m1's set_call_rate)
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local symbol_picker = require("telescope-m1.symbol_picker")

local function rate_value(label)
  return label:lower():match("startup") and "startup" or (label:gsub("Hz$", ""))
end

---@param opts? table
return function(opts)
  opts = opts or {}
  local ok, nvim_m1 = pcall(require, "nvim-m1")
  if not ok then
    vim.notify("telescope-m1: the call_rates picker needs nvim-m1", vim.log.levels.WARN)
    return
  end
  local project = require("nvim-m1.project")
  local rates = project.rates(nvim_m1.config)
  if #rates == 0 then
    vim.notify(
      "telescope-m1: no execution-rate clocks found (no project?)",
      vim.log.levels.INFO
    )
    return
  end

  pickers
    .new(opts, {
      prompt_title = "M1 Execution Rates",
      finder = finders.new_table({ results = rates }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(bufnr, map)
        -- <CR>: the scripts scheduled at the picked rate, via the LSP's
        -- `rate:` workspace-symbol facet.
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          actions.close(bufnr)
          local hz = rate_value(entry[1])
          if hz == "startup" then
            vim.notify(
              "telescope-m1: startup scripts carry no rate facet",
              vim.log.levels.INFO
            )
            return
          end
          symbol_picker.from_lsp(opts, {
            title = "M1 Scripts @ " .. entry[1],
            query = "rate:" .. hz,
          })
        end)
        -- <C-a>: assign a script to this rate.
        map({ "i", "n" }, "<C-a>", function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          actions.close(bufnr)
          local rate = rate_value(entry[1])
          vim.ui.input({ prompt = "Script (Root.…): " }, function(script)
            if not script or script == "" then
              return
            end
            -- Delegate to nvim-m1's serialized async mutation runner (#26):
            -- set_call_rate_for owns the queueing, error reporting, and the
            -- LSP reload notification, so the picker never blocks the UI or
            -- races a concurrent project mutation. Public as of nvim-m1
            -- v0.11.0; degrade with a clear message on an older install.
            if not project.set_call_rate_for then
              vim.notify(
                "telescope-m1: update nvim-m1 (v0.11.0+) to assign call rates from this picker",
                vim.log.levels.WARN
              )
              return
            end
            project.set_call_rate_for(nvim_m1.config, script, rate, {
              label = script .. " call rate -> " .. entry[1],
            })
          end)
        end)
        return true
      end,
    })
    :find()
end
