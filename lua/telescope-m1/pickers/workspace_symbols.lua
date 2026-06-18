--- telescope-m1: workspace symbol picker — flat fuzzy search over every
--- channel, parameter, enum and function in the loaded project (via m1-lsp).
---
--- m1-lsp's `workspace/symbol` understands faceted queries — whitespace-
--- separated `key:value` tokens that filter server-side before the free text
--- substring-matches the path (see m1-lsp workspace_symbol.rs):
---   tag:<name>        symbols carrying the tag (own or inherited)
---   security:<level>  by `Props Security` (case-insensitive)
---   rate:<hz>         functions/methods scheduled at that rate
---   type:<enum|float|integer|unsigned|boolean|string>  by value type
--- These slices ("every Tune-security channel", "every enum channel", "every
--- parameter tagged Engine") are exactly what an M1 user wants and the LSP
--- already computes them, but Telescope's prompt only fuzzy-filters the rows it
--- was handed once — typing `type:enum` into the prompt matches nothing because
--- the facet text is never in the display, so the slice was unreachable.
---
--- We compose those facets from picker opts into the LSP query, so
---   :Telescope m1 workspace_symbols type=enum security=Tune
--- (and the programmatic `opts.type`/`security`/`tag`/`rate`) reach the server
--- verbatim, mirroring VS Code's symbol box. `opts.query` free text is kept and
--- appended after the facets, exactly as the LSP expects.
local symbol_picker = require("telescope-m1.symbol_picker")

--- The facet opts the picker forwards to the LSP, in `opt -> facet key` form.
--- Order is fixed so the composed query is deterministic (testable).
local FACETS = {
  { opt = "tag", key = "tag" },
  { opt = "security", key = "security" },
  { opt = "rate", key = "rate" },
  { opt = "type", key = "type" },
}

--- Build the `workspace/symbol` query string from picker opts: the facet
--- shorthands (`opts.type`, `opts.security`, `opts.tag`, `opts.rate`) become
--- leading `key:value` tokens, followed by any free `opts.query` text.
--- Pure, so the composition is unit-testable without a picker/LSP.
---@param opts table
---@return string query
local function compose_query(opts)
  local tokens = {}
  for _, f in ipairs(FACETS) do
    local v = opts[f.opt]
    if v ~= nil and v ~= "" then
      tokens[#tokens + 1] = f.key .. ":" .. tostring(v)
    end
  end
  local free = opts.query
  if free ~= nil and free ~= "" then
    tokens[#tokens + 1] = free
  end
  return table.concat(tokens, " ")
end

---@param opts? table  Standard telescope picker options, plus optional facet
---  shorthands `type`/`security`/`tag`/`rate` and free-text `query`.
local function picker(opts)
  opts = opts or {}
  symbol_picker.from_lsp(opts, {
    title = "M1 Workspace Symbols",
    query = compose_query(opts),
  })
end

-- The picker is callable — `require(...)(opts)` still works — but is a table so
-- `compose_query` can be exposed (underscore-prefixed) for the unit tests to
-- invoke the real source.
local M = setmetatable({}, {
  __call = function(_, opts)
    return picker(opts)
  end,
})

-- Private-by-convention handle for the unit tests.
M._compose_query = compose_query

return M
