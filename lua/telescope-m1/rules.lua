--- telescope-m1: the m1-lint rule registry.
---
--- The catalogue is owned by m1-lint and read at runtime from the bundled
--- binary (`m1-lint --rules --format json`, schema v2 with severity + summary
--- — C-Nucifora/m1-lint#118), so a new m1-lint release shows its rules here
--- with zero changes to this repo. The static table below is only the
--- fallback for sessions with no m1-lint binary at all; a v1 binary (no
--- severity/summary fields) gets those synthesized. Results are cached per
--- session (`M.reset()` clears).
local M = {}

--- Base documentation URL (the README "Rules" section).
M.docs_url = "https://github.com/C-Nucifora/m1-lint#rules"

---@class M1LintRule
---@field code string
---@field name string
---@field severity "error"|"warning"
---@field fixable boolean
---@field summary string

--- Fallback only — used when no m1-lint binary can be resolved at all.
---@type M1LintRule[]
M.fallback_rules = {
  {
    code = "L001",
    name = "line-too-long",
    severity = "warning",
    fixable = false,
    summary = "line exceeds the configured maximum length",
  },
  {
    code = "L002",
    name = "trailing-whitespace",
    severity = "warning",
    fixable = true,
    summary = "trailing whitespace at end of line",
  },
  {
    code = "L003",
    name = "missing-final-newline",
    severity = "warning",
    fixable = true,
    summary = "file does not end with a newline",
  },
  {
    code = "L004",
    name = "eq-operator-preferred",
    severity = "warning",
    fixable = true,
    summary = "prefer `eq` over `==`",
  },
  {
    code = "L005",
    name = "logical-operator-preferred",
    severity = "warning",
    fixable = true,
    summary = "prefer the spelled logical operators (and/or/not)",
  },
  {
    code = "L006",
    name = "float-eq-comparison",
    severity = "error",
    fixable = false,
    summary = "float compared with an equality operator",
  },
  {
    code = "L007",
    name = "operator-spacing",
    severity = "warning",
    fixable = true,
    summary = "missing space around an operator",
  },
  {
    code = "L008",
    name = "nesting-too-deep",
    severity = "warning",
    fixable = false,
    summary = "block nesting exceeds the configured depth",
  },
  {
    code = "L009",
    name = "cyclomatic-complexity",
    severity = "warning",
    fixable = false,
    summary = "function cyclomatic complexity too high",
  },
  {
    code = "L010",
    name = "indentation-style",
    severity = "warning",
    fixable = false,
    summary = "indentation does not match the configured style",
  },
  {
    code = "L011",
    name = "comment-style",
    severity = "warning",
    fixable = true,
    summary = "comment-style violation",
  },
  {
    code = "L012",
    name = "unused-local",
    severity = "warning",
    fixable = false,
    summary = "local binding is never used",
  },
  -- Note: m1-lint defines no L013; the catalogue jumps from L012 to L014.
  {
    code = "L014",
    name = "expand-undefined-variable",
    severity = "error",
    fixable = false,
    summary = "expand references a variable that is not defined",
  },
  {
    code = "L015",
    name = "local-missing-initializer",
    severity = "warning",
    fixable = false,
    summary = "local declared without an initializer",
  },
  {
    code = "L016",
    name = "local-variable-naming",
    severity = "warning",
    fixable = false,
    summary = "local name does not follow the naming convention",
  },
  {
    code = "L017",
    name = "magic-number",
    severity = "warning",
    fixable = false,
    summary = "unnamed numeric literal (magic number)",
  },
  {
    code = "L018",
    name = "semicolon-spacing",
    severity = "warning",
    fixable = true,
    summary = "incorrect spacing around a semicolon",
  },
  {
    code = "L019",
    name = "cognitive-complexity",
    severity = "warning",
    fixable = false,
    summary = "function cognitive complexity exceeds the configured maximum",
  },
  {
    code = "L020",
    name = "object-naming",
    severity = "warning",
    fixable = false,
    summary = "object names begin with an uppercase letter (manual p.64)",
  },
  {
    code = "L021",
    name = "one-statement-per-line",
    severity = "warning",
    fixable = false,
    summary = "write only one statement per line (manual p.65)",
  },
  {
    code = "L022",
    name = "keyword-paren-spacing",
    severity = "warning",
    fixable = true,
    summary = "put a space between a keyword and a parenthesis (`if (`)",
  },
  {
    code = "L023",
    name = "call-paren-spacing",
    severity = "warning",
    fixable = true,
    summary = "no space between a function name and its parenthesis",
  },
  {
    code = "L024",
    name = "ternary-condition-parens",
    severity = "warning",
    fixable = true,
    summary = "ternary condition wrapped in parentheses: (condition) ? a : b",
  },
  {
    code = "L025",
    name = "local-scope-too-wide",
    severity = "warning",
    fixable = false,
    summary = "local declared in a wider scope than its uses need",
  },
}

--- All rules, in code order: the bundled binary's catalogue when available
--- (cached per session), else the static fallback.
---@return M1LintRule[]
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
    list[#list + 1] = {
      code = code,
      name = r.name,
      -- A v1 binary emits no severity/summary; synthesize so the picker
      -- renders every rule either way.
      severity = r.severity or "warning",
      fixable = r.fixable or false,
      summary = r.summary or (r.name and r.name:gsub("%-", " ") or ""),
    }
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

--- Parse `m1-lint --rules --format json` output into
--- `{ code = { name, fixable, severity?, summary? } }` (severity/summary are
--- present from catalogue schema v2). Returns nil if the output is
--- unparseable (e.g. an older m1-lint without `--rules`).
---@param output string
---@return table<string, { name: string, fixable: boolean, severity: string?, summary: string? }>?
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
      by_code[r.code] = {
        name = r.name,
        fixable = r.fixable,
        severity = r.severity,
        summary = r.summary,
      }
    end
  end
  return by_code
end

--- Resolve the m1-lint command, preferring the binary nvim-m1 manages (which
--- may be bundled under `stdpath("data")` and not on `$PATH`) and falling back
--- to a plain `$PATH` lookup. Mirrors how `telescope-m1/lsp.lua` defers to
--- nvim-m1 so the two never disagree about which toolchain is in use.
---@return string?  An executable command/path for m1-lint, or nil.
local function resolve_m1_lint()
  local ok, install = pcall(require, "nvim-m1.install")
  if ok and type(install.resolve) == "function" then
    local resolved = install.resolve("m1-lint")
    if resolved then
      return resolved
    end
  end
  if vim.fn.executable("m1-lint") == 1 then
    return "m1-lint"
  end
  return nil
end

--- Query the m1-lint binary for its rule catalogue, or nil if unavailable.
--- Resolves the bundled nvim-m1 binary too (not just `$PATH`), so the rules
--- sync test runs whenever the plugin is installed.
---@return table<string, { name: string, fixable: boolean }>?
function M.binary_catalogue()
  local cmd = resolve_m1_lint()
  if not cmd then
    return nil
  end
  local out = vim.fn.system({ cmd, "--rules", "--format", "json" })
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return M.parse_catalogue(out)
end

return M
