--- telescope-m1: talking to m1-lsp.
local M = {}

--- Client names that identify an m1-lsp server, in preference order. The
--- canonical name comes from nvim-m1 (the plugin that registers the server) so
--- the two never disagree; the rest are fallbacks for other setups.
local function client_names()
  local names = {}
  local ok, nvim_m1_lsp = pcall(require, "nvim-m1.lsp")
  if ok and nvim_m1_lsp.client_name then
    names[#names + 1] = nvim_m1_lsp.client_name
  end
  for _, n in ipairs({ "m1lsp", "m1_lsp", "m1-lsp" }) do
    if not vim.tbl_contains(names, n) then
      names[#names + 1] = n
    end
  end
  return names
end

--- Find one M1 client attached to the invocation buffer. Ambiguity is an error.
---@param bufnr? integer
---@return vim.lsp.Client?, string?
function M.find_client(bufnr)
  local candidates = {}
  local names = client_names()
  for _, client in
    ipairs(vim.lsp.get_clients({ bufnr = bufnr or vim.api.nvim_get_current_buf() }))
  do
    if
      vim.tbl_contains(names, client.name)
      or vim.tbl_contains((client.config or {}).filetypes or {}, "m1scr")
    then
      candidates[#candidates + 1] = client
    end
  end
  if #candidates == 1 then
    return candidates[1]
  end
  if #candidates > 1 then
    return nil,
      "multiple M1 clients attached; detach the extra client before opening this picker"
  end
  return nil, "no m1-lsp client attached; open a .m1scr file in the project first"
end

--- Keep the client, request buffer and server project together across UI callbacks.
function M.capture_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local client, err = M.find_client(bufnr)
  local root = client and (client.root_dir or (client.config or {}).root_dir)
  local prj
  if type(root) == "string" and root ~= "" then
    local candidate = vim.fs.normalize(root .. "/Project.m1prj")
    if vim.fn.filereadable(candidate) == 1 then
      prj = candidate
    end
  end
  return { client = client, bufnr = bufnr, project_file = prj, error = err }
end

--- Issue an LSP request across the 0.10/0.11 `vim.lsp.Client.request` change.
---
--- Neovim 0.11 turned `Client.request` into a proper method (it reads `self`),
--- so it must be called with the colon form. On 0.10 (this plugin's stated
--- minimum) `request` was a plain function `(method, params, handler, bufnr)`
--- with no `self`, so a colon call passed the client as `method` and shifted
--- every argument — breaking every LSP-backed picker. Branch on the version so
--- both work.
---@param client vim.lsp.Client
---@param method string
---@param params table
---@param handler fun(err: any, result: any)
---@return boolean ok
local function client_request(client, method, params, handler, bufnr)
  if vim.fn.has("nvim-0.11") == 1 then
    return client:request(method, params, handler, bufnr)
  end
  return client.request(method, params, handler, bufnr)
end

--- Short label for an LSP SymbolKind number (e.g. 13 -> "Variable").
---@param kind integer
---@return string
function M.kind_label(kind)
  local names = vim.lsp.protocol.SymbolKind
  return (type(names) == "table" and names[kind]) or "Symbol"
end

--- Single-glyph icon for an LSP SymbolKind, for the picker display column.
--- Two sets (#27): plain ASCII (default, no font requirements) and Nerd Font
--- glyphs (opt-in via `icons = "nerd"`); `icons = false` blanks the column.
local KIND_ICON = {
  ascii = {
    Variable = "C", -- channel
    Property = "P", -- parameter
    Constant = "K",
    Function = "F",
    Method = "M",
    Array = "T", -- table
    Namespace = "G", -- group
    Object = "O",
  },
  nerd = {
    Variable = "\u{f0c1e}", -- 󰰞 nf-md-alpha_c_box (channel)
    Property = "\u{f0c46}", -- 󰱆 nf-md-alpha_p_box (parameter)
    Constant = "\u{eb5d}", -- nf-cod-symbol_constant
    Function = "\u{f0295}", -- 󰊕 nf-md-function
    Method = "\u{ea8c}", --  nf-cod-symbol_method
    Array = "\u{ea8a}", --  nf-cod-symbol_array
    Namespace = "\u{ea8b}", --  nf-cod-symbol_namespace
    Object = "\u{eb63}", --  nf-cod-symbol_misc
  },
}
function M.kind_icon(kind)
  local style = require("telescope-m1.config").options.icons
  if style == false then
    return ""
  end
  local set = KIND_ICON[style] or KIND_ICON.ascii
  return set[M.kind_label(kind)] or ""
end

--- Convert an LSP `SymbolInformation` into a telescope-friendly entry value.
--- Pure: no editor calls beyond URI decoding, so it is unit-testable.
---@param sym table  LSP SymbolInformation
---@return table { name, container, kind, kind_label, filename, lnum, col }
function M.symbol_to_entry(sym)
  local loc = sym.location or {}
  local range = loc.range or {}
  local start = range.start or { line = 0, character = 0 }
  local filename = loc.uri and vim.uri_to_fname(loc.uri) or ""
  return {
    name = sym.name,
    container = sym.containerName,
    kind = sym.kind,
    kind_label = M.kind_label(sym.kind),
    filename = filename,
    lnum = (start.line or 0) + 1,
    col = (start.character or 0) + 1,
  }
end

--- Arrange symbol entries as a component hierarchy: sorted by their dotted path
--- with a `depth` (number of `.` separators) for indentation. Pure, so the
--- components picker's presentation can be unit-tested.
---@param entries table[]  Entries from `symbol_to_entry`.
---@return table[] ordered  Same entries, sorted, each with a `depth` field.
function M.build_hierarchy(entries)
  local ordered = vim.deepcopy(entries)
  table.sort(ordered, function(a, b)
    return (a.name or "") < (b.name or "")
  end)
  for _, e in ipairs(ordered) do
    local _, dots = (e.name or ""):gsub("%.", "")
    e.depth = dots
  end
  return ordered
end

--- Request workspace symbols matching `query` (empty = all). Calls `cb` with a
--- list of entry tables (see `symbol_to_entry`), or an error string.
---@param query string
---@param cb fun(entries: table[]?, err: string?)
function M.workspace_symbols(query, cb, context)
  context = context or M.capture_context()
  local client = context.client
  if not client then
    return cb(
      nil,
      context.error or "no m1-lsp client attached to the originating buffer"
    )
  end

  local completed = false
  local function finish(entries, err)
    if completed then
      return
    end
    completed = true
    cb(entries, err)
  end
  local ok, accepted = pcall(function()
    return client_request(
      client,
      "workspace/symbol",
      { query = query or "" },
      function(err, result)
        if err then
          return finish(nil, err.message or tostring(err))
        end
        local entries = {}
        for _, sym in ipairs(result or {}) do
          local entry = M.symbol_to_entry(sym)
          entry.project_file = context.project_file
          entries[#entries + 1] = entry
        end
        finish(entries)
      end,
      context.bufnr
    )
  end)
  if not ok or accepted == false then
    finish(nil, "workspace/symbol request failed")
  end
end

return M
