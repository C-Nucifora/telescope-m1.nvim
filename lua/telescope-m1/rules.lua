--- telescope-m1: the m1-lint rule registry.
---
--- The structural facts (code, name, fixability) are owned by m1-lint and can be
--- enumerated with `m1-lint --rules --format json`. This table additionally
--- carries presentation-only metadata m1-lint does not emit (severity colour,
--- one-line summary). A test (`rules_spec`) runs `m1-lint --rules` and asserts
--- the codes/names/fixability here match the binary, so the catalogue cannot
--- silently drift from the toolchain.
local M = {}

--- Base documentation URL (the README "Rules" section).
M.docs_url = "https://github.com/C-Nucifora/m1-lint#rules"

---@class M1LintRule
---@field code string
---@field name string
---@field severity "error"|"warning"
---@field fixable boolean
---@field summary string

---@type M1LintRule[]
M.rules = {
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
}

--- All rules, in code order.
---@return M1LintRule[]
function M.all()
  return M.rules
end

--- Parse `m1-lint --rules --format json` output into `{ code = { name, fixable } }`.
--- Returns nil if the binary is missing or the output is unparseable (e.g. an
--- older m1-lint without `--rules`).
---@param output string
---@return table<string, { name: string, fixable: boolean }>?
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
      by_code[r.code] = { name = r.name, fixable = r.fixable }
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
