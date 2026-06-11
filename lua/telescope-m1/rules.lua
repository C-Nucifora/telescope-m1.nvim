--- telescope-m1: the m1-lint rule registry.
---
--- The registry is built at runtime from `m1-lint --rules --format json`
--- (catalogue v2: code/name/severity/fixable/summary — the same binary the
--- lint diagnostics come from), cached per session. Only presentation
--- concerns live here: the docs URL and the severity→highlight mapping. A
--- static snapshot is kept purely as a fallback for when no m1-lint binary
--- can be resolved; it is NOT load-bearing, no test asserts it is current,
--- and it may go stale without breaking anything (#14).
local M = {}

--- Base documentation URL (the README "Rules" section).
M.docs_url = "https://github.com/C-Nucifora/m1-lint#rules"

---@class M1LintRule
---@field code string
---@field name string
---@field severity string
---@field fixable boolean
---@field summary string

--- Severity → highlight group for the picker. Severities this plugin has
--- never heard of (a future m1-lint may add some) degrade to DiagnosticInfo
--- rather than erroring.
local severity_hl = {
  error = "DiagnosticError",
  warning = "DiagnosticWarn",
}

---@param severity string?
---@return string highlight group
function M.severity_hl(severity)
  return severity_hl[severity] or "DiagnosticInfo"
end

--- Compact severity label for the picker's fixed-width column.
---@param severity string?
---@return string
function M.severity_label(severity)
  if type(severity) ~= "string" or severity == "" then
    return "?"
  end
  if severity == "warning" then
    return "warn"
  end
  return severity:sub(1, 5)
end

--- Fallback snapshot of the catalogue (m1-lint v0.14.0), used only when no
--- m1-lint binary is resolvable. Allowed to go stale.
---@type M1LintRule[]
local fallback = {
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

--- Parse `m1-lint --rules --format json` output into an M1LintRule[].
--- Understands catalogue v2 (severity + summary); v1 entries (code/name/
--- fixable only, pre-#118 m1-lint) get severity "warning" and a summary
--- synthesised from the rule name, so the picker still renders sensibly.
--- Returns nil if the output is missing, unparseable or has no rules.
---@param output string?
---@return M1LintRule[]?
function M.parse_catalogue(output)
  if not output or output == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, output)
  if not ok or type(data) ~= "table" or type(data.rules) ~= "table" then
    return nil
  end
  local out = {}
  for _, r in ipairs(data.rules) do
    if type(r) == "table" and type(r.code) == "string" and type(r.name) == "string" then
      out[#out + 1] = {
        code = r.code,
        name = r.name,
        severity = type(r.severity) == "string" and r.severity or "warning",
        fixable = r.fixable == true,
        summary = type(r.summary) == "string" and r.summary or (r.name:gsub("%-", " ")),
      }
    end
  end
  if #out == 0 then
    return nil
  end
  return out
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
---@return M1LintRule[]?
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

--- The per-session registry cache; nil until the first `all()`.
---@type M1LintRule[]?
local cache = nil

--- Drop the cached registry (tests; or after nvim-m1 swaps binaries).
function M._invalidate()
  cache = nil
end

--- All rules, in the binary's order, from the resolved m1-lint binary when
--- one is available and the fallback snapshot otherwise. Cached per session.
---@return M1LintRule[]
function M.all()
  if cache then
    return cache
  end
  cache = M.binary_catalogue() or fallback
  return cache
end

return M
