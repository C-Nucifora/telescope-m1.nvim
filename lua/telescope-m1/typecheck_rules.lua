--- telescope-m1: the m1-typecheck T-code registry.
---
--- The catalogue is owned by m1-typecheck and read at runtime from the bundled
--- binary (`m1-typecheck --rules --format json`, `{version,rules:[{code,name}]}`
--- — C-Nucifora/m1-typecheck), so a new m1-typecheck release shows its T-codes
--- here with zero changes to this repo. The static table below is only the
--- fallback for sessions with no m1-typecheck binary at all. Unlike the lint
--- catalogue, the T-code catalogue carries no severity/fixable/summary fields —
--- a typecheck finding's severity is context-dependent (config- and
--- flag-driven), so the picker shows code + name only. Results are cached per
--- session (`M.reset()` clears).
local M = {}

--- Base documentation URL. m1-typecheck's README has no per-T-code anchors (its
--- checks are described narratively under "How it works"), so — unlike the lint
--- catalogue — there is no deep-link per rule; `<CR>` opens that section.
M.docs_url = "https://github.com/C-Nucifora/m1-typecheck#how-it-works"

--- Deep-link for a T-code. m1-typecheck publishes no anchor-stable per-rule
--- headings, so every rule resolves to the same "How it works" section. Kept as
--- a function so the picker calls the same shape as the lint picker and can gain
--- deep links for free if the README ever grows anchored rule headings.
---@param _rule { name: string?, code: string? }?
---@return string
function M.docs_url_for(_rule)
  return M.docs_url
end

---@class M1TypeCheckRule
---@field code string
---@field name string

--- Fallback only — used when no m1-typecheck binary can be resolved at all.
--- Snapshot of `m1-typecheck --rules --format json` at v0.51.0 (T001–T111, with
--- the catalogue's natural gaps). The sync spec fails if the released binary
--- drifts from this list, so it belongs in the same release cascade.
---@type M1TypeCheckRule[]
M.fallback_rules = {
  { code = "T001", name = "unresolved-reference" },
  { code = "T002", name = "float-equality" },
  { code = "T003", name = "int-float-mixing" },
  { code = "T004", name = "signed-unsigned-comparison" },
  { code = "T005", name = "modulo-on-float" },
  { code = "T006", name = "bitwise-on-float" },
  { code = "T010", name = "invalid-component-parent" },
  { code = "T020", name = "enum-non-member" },
  { code = "T021", name = "enum-numeric-comparison" },
  { code = "T030", name = "assignment-type-mismatch" },
  { code = "T031", name = "unresolved-assignment-target" },
  { code = "T040", name = "channel-multiple-assignment" },
  { code = "T041", name = "missing-cfg-parameter" },
  { code = "T042", name = "dbc-signal-range" },
  { code = "T050", name = "symbol-name-convention" },
  { code = "T060", name = "stateful-conditional" },
  { code = "T061", name = "integrated-only-call" },
  { code = "T062", name = "deprecated-overload" },
  { code = "T063", name = "calibration-only-call" },
  { code = "T064", name = "wrong-argument-count" },
  { code = "T065", name = "intrinsic-argument-type-mismatch" },
  { code = "T070", name = "when-is-exhaustive" },
  { code = "T071", name = "name-case-collision" },
  { code = "T080", name = "invalid-value-reaches-finite-sink" },
  { code = "T081", name = "nan-to-integer" },
  { code = "T082", name = "when-subject-not-enum" },
  { code = "T083", name = "static-local-initialiser" },
  { code = "T084", name = "expand-bounds" },
  { code = "T085", name = "user-argument-mismatch" },
  { code = "T086", name = "unit-mismatch" },
  { code = "T087", name = "type-restricted-to-locals" },
  { code = "T088", name = "circular-dependency" },
  { code = "T089", name = "rate-inversion" },
  { code = "T090", name = "expression-nesting-too-deep" },
  { code = "T091", name = "local-object-case-ambiguity" },
  { code = "T092", name = "untagged-component" },
  { code = "T093", name = "unassigned-channel" },
  { code = "T094", name = "unread-parameter" },
  { code = "T095", name = "invalid-display-unit" },
  { code = "T096", name = "multiple-scheduled-writers" },
  { code = "T097", name = "recursive-call" },
  { code = "T098", name = "unused-argument" },
  { code = "T099", name = "return-value-not-assigned" },
  { code = "T100", name = "bare-parameter-reference" },
  { code = "T101", name = "return-statement" },
  { code = "T102", name = "channel-multiple-assignment-cross-function" },
  { code = "T103", name = "ambiguous-reference" },
  { code = "T104", name = "unscheduled-function" },
  { code = "T105", name = "local-use-before-definition" },
  { code = "T106", name = "group-not-a-value-provider" },
  { code = "T107", name = "dbc-init-missing" },
  { code = "T108", name = "dbc-unresolved-reference" },
  { code = "T109", name = "dbc-message-direction" },
  { code = "T110", name = "dbc-signal-accessor-type" },
  { code = "T111", name = "flash-without-preserve" },
}

--- All T-codes, in code order: the bundled binary's catalogue when available
--- (cached per session), else the static fallback.
---@return M1TypeCheckRule[]
function M.all()
  if M._cache then
    return M._cache
  end
  local catalogue = M.binary_catalogue()
  if not catalogue then
    return M.fallback_rules
  end
  local list = {}
  for code, r in pairs(catalogue) do
    list[#list + 1] = { code = code, name = r.name }
  end
  table.sort(list, function(a, b)
    return a.code < b.code
  end)
  M._cache = list
  return list
end

--- Drop the per-session cache (tests; after a toolchain update).
function M.reset()
  M._cache = nil
end

--- Parse `m1-typecheck --rules --format json` into `{ code = { name } }`.
--- Returns nil if the output is unparseable (e.g. an m1-typecheck without
--- `--rules`).
---@param output string
---@return table<string, { name: string }>?
function M.parse_catalogue(output)
  if not output or output == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, output)
  if not ok or type(data) ~= "table" or type(data.rules) ~= "table" then
    return nil
  end
  local by_code = {}
  for _, r in ipairs(data.rules) do
    if r.code then
      by_code[r.code] = { name = r.name }
    end
  end
  return by_code
end

--- Resolve the m1-typecheck command, preferring the binary nvim-m1 manages and
--- falling back to a `$PATH` lookup. Mirrors `telescope-m1.rules`' resolution
--- of m1-lint so the two never disagree about which toolchain is in use.
---@return string?  An executable command/path for m1-typecheck, or nil.
local function resolve_m1_typecheck()
  local ok, install = pcall(require, "nvim-m1.install")
  if ok and type(install.resolve) == "function" then
    local resolved = install.resolve("m1-typecheck")
    if resolved then
      return resolved
    end
  end
  if vim.fn.executable("m1-typecheck") == 1 then
    return "m1-typecheck"
  end
  return nil
end

--- Query the m1-typecheck binary for its T-code catalogue, or nil if
--- unavailable.
---@return table<string, { name: string }>?
function M.binary_catalogue()
  local cmd = resolve_m1_typecheck()
  if not cmd then
    return nil
  end
  -- :wait(5000) pumps the event loop (vs vim.fn.system's hard block) and the
  -- timeout turns a hung binary into a clean fall-through to the static table,
  -- not a frozen UI — mirroring nvim-m1's project queries.
  local ok, res = pcall(function()
    return vim
      .system({ cmd, "--rules", "--format", "json" }, { text = true })
      :wait(5000)
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  return M.parse_catalogue(res.stdout)
end

--- Public alias so a health check can report the resolved m1-typecheck path
--- without duplicating the nvim-m1-aware resolution logic.
M.resolve_m1_typecheck = resolve_m1_typecheck

return M
