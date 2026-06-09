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
            -- Reuse nvim-m1's runner via its public command path: set-call-rate
            -- needs the same plumbing, so go through project.set_call_rate-like
            -- flow with the rate preselected.
            local cfg = nvim_m1.config
            local bin = project.resolve_cmd(cfg)
            local prj = project.project_file()
            if not bin or not prj then
              vim.notify(
                "telescope-m1: m1-project or Project.m1prj not found",
                vim.log.levels.ERROR
              )
              return
            end
            local out = vim.fn.system({
              bin,
              "set-call-rate",
              "--project",
              prj,
              "--script",
              script,
              "--rate",
              rate,
            })
            if vim.v.shell_error ~= 0 then
              vim.notify(
                "telescope-m1: set-call-rate failed: " .. out,
                vim.log.levels.ERROR
              )
              return
            end
            local name = require("nvim-m1.lsp").client_name
            local uri = vim.uri_from_fname(prj)
            for _, client in ipairs(vim.lsp.get_clients({ name = name })) do
              client.notify("workspace/didChangeWatchedFiles", {
                changes = { { uri = uri, type = 2 } },
              })
            end
            vim.notify("telescope-m1: " .. script .. " call rate -> " .. entry[1])
          end)
        end)
        return true
      end,
    })
    :find()
end
