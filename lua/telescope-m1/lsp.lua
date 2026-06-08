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

--- Find the active m1-lsp client.
---
--- Prefers a client named like m1-lsp; otherwise any client configured for the
--- `m1scr` filetype. We deliberately do NOT fall back to "any client
--- advertising workspace-symbol support": general-purpose servers (lua_ls,
--- pyright, …) all advertise `workspaceSymbolProvider`, so that fallback would
--- pick the wrong server and present its (non-M1) symbols as M1 components.
--- Only the `m1scr` filetype is a reliable M1 signal.
---@return vim.lsp.Client?
function M.find_client()
  local clients = vim.lsp.get_clients()

  for _, want in ipairs(client_names()) do
    for _, c in ipairs(clients) do
      if c.name == want then
        return c
      end
    end
  end

  for _, c in ipairs(clients) do
    local fts = (c.config or {}).filetypes or {}
    if vim.tbl_contains(fts, "m1scr") then
      return c
    end
  end

  return nil
end

--- Short label for an LSP SymbolKind number (e.g. 13 -> "Variable").
---@param kind integer
---@return string
function M.kind_label(kind)
  local names = vim.lsp.protocol.SymbolKind
  return (type(names) == "table" and names[kind]) or "Symbol"
end

--- Single-glyph icon for an LSP SymbolKind, for the picker display column.
local KIND_ICON = {
  Variable = "", -- channel
  Property = "", -- parameter
  Constant = "",
  Function = "",
  Method = "",
  Array = "", -- table
  Namespace = "", -- group
  Object = "",
}
function M.kind_icon(kind)
  return KIND_ICON[M.kind_label(kind)] or ""
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
function M.workspace_symbols(query, cb)
  local client = M.find_client()
  if not client then
    return cb(
      nil,
      "no m1-lsp client attached — open a .m1scr file in the project first"
    )
  end

  local ok = pcall(function()
    client:request("workspace/symbol", { query = query or "" }, function(err, result)
      if err then
        return cb(nil, err.message or tostring(err))
      end
      local entries = {}
      for _, sym in ipairs(result or {}) do
        entries[#entries + 1] = M.symbol_to_entry(sym)
      end
      cb(entries)
    end)
  end)
  if not ok then
    cb(nil, "workspace/symbol request failed")
  end
end

return M
