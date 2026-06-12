--- telescope-m1: component detail-card previewer (#23).
---
--- Project components (channels/parameters/…) resolve to their `<Component>`
--- line inside Project.m1prj, so the stock quickfix previewer showed a window
--- of raw nested XML — and made the previewer open a 12k-line XML buffer on
--- every selection movement. Instead, entries located in a `.m1prj` render a
--- small detail card (path, class, type, unit, security, rate, tags, comment)
--- from `m1-project list-components --json`, fetched once per picker open;
--- script-backed entries keep the normal file preview.
local M = {}

--- Render the card lines for a picker entry value + optional details record.
--- Pure (no editor calls), so it is unit-testable.
---@param sym { name?: string, kind_label?: string, container?: string }
---@param details? table  One record from `list-components --json`.
---@return string[] lines
function M.render_card(sym, details)
  local name = sym.name or "?"
  local lines = { name, string.rep("─", math.max(vim.fn.strdisplaywidth(name), 8)) }
  local function add(label, value)
    if value ~= nil and value ~= vim.NIL and tostring(value) ~= "" then
      lines[#lines + 1] = string.format("%-9s %s", label, tostring(value))
    end
  end
  add("kind", sym.kind_label)
  if details then
    add("class", details.classname)
    add("type", details.type)
    add("unit", details.unit)
    add("security", details.security)
    add("rate", details.call_rate)
    add("qty", details.qty)
    if type(details.tags) == "table" and #details.tags > 0 then
      add("tags", table.concat(details.tags, ", "))
    end
    if
      details.comment ~= nil
      and details.comment ~= vim.NIL
      and details.comment ~= ""
    then
      lines[#lines + 1] = ""
      for _, l in ipairs(vim.split(tostring(details.comment), "\n", { plain = true })) do
        lines[#lines + 1] = l
      end
    end
  end
  return lines
end

--- Look up a component record by symbol name, tolerating the `Root.` prefix
--- difference between the LSP's symbol names and `list-components` paths.
---@param map table<string, table>
---@param name string
---@return table?
function M.lookup(map, name)
  return map[name] or map["Root." .. name] or map[(name:gsub("^Root%.", ""))]
end

--- Fetch `m1-project list-components --json` once, asynchronously, building a
--- path -> record map. Calls `cb(nil)` when m1-project/nvim-m1/the project is
--- unavailable — the previewer then renders the basic card only.
---@param cb fun(map: table<string, table>?)
function M.fetch_details(cb)
  local ok, nvim_m1 = pcall(require, "nvim-m1")
  if not ok or type(nvim_m1.config) ~= "table" then
    return cb(nil) -- nvim-m1 absent or not set up (e.g. headless tests)
  end
  local project = require("nvim-m1.project")
  local resolved, bin = pcall(project.resolve_cmd, nvim_m1.config)
  local prj = project.project_file()
  if not resolved or not bin or not prj then
    return cb(nil)
  end
  vim.system({ bin, "list-components", "--json", "--project", prj }, {}, function(res)
    if res.code ~= 0 or not res.stdout or res.stdout == "" then
      return vim.schedule(function()
        cb(nil)
      end)
    end
    local decoded_ok, records = pcall(vim.json.decode, res.stdout)
    if not decoded_ok or type(records) ~= "table" then
      return vim.schedule(function()
        cb(nil)
      end)
    end
    local map = {}
    for _, r in ipairs(records) do
      if type(r) == "table" and r.path then
        map[r.path] = r
      end
    end
    vim.schedule(function()
      cb(map)
    end)
  end)
end

--- A previewer that renders the detail card for `.m1prj`-located entries and
--- falls back to the normal buffer preview for script-backed ones.
---@param opts table
function M.previewer(opts)
  local previewers = require("telescope.previewers")
  local details ---@type table<string, table>?
  M.fetch_details(function(map)
    details = map
  end)
  return previewers.new_buffer_previewer({
    title = "M1 Component",
    get_buffer_by_name = function(_, entry)
      return entry.value.name or entry.filename
    end,
    define_preview = function(self, entry)
      local fname = entry.filename or ""
      if fname:sub(-6) ~= ".m1prj" then
        require("telescope.config").values.buffer_previewer_maker(
          fname,
          self.state.bufnr,
          {
            bufname = self.state.bufname,
            winid = self.state.winid,
          }
        )
        return
      end
      local rec = details and M.lookup(details, entry.value.name or "") or nil
      local lines = M.render_card(entry.value, rec)
      vim.bo[self.state.bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].modifiable = false
    end,
  })
end

return M
