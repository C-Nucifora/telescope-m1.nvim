local rules = require("telescope-m1.rules")

-- Schema-shape assertions only (#14): the catalogue is read from the m1-lint
-- binary at runtime, so a newer m1-lint adding rules must NOT fail this suite.
describe("telescope-m1.rules", function()
  before_each(function()
    rules.reset()
  end)

  it("lists rules in code order with unique codes", function()
    local all = rules.all()
    local catalogue = rules.binary_catalogue()
    if catalogue then
      local n = 0
      for _ in pairs(catalogue) do
        n = n + 1
      end
      assert.equals(n, #all, "all() mirrors the binary catalogue")
    else
      assert.is_true(#all >= 26, "fallback table regressed: " .. #all)
    end
    local seen = {}
    local prev = ""
    for _, r in ipairs(all) do
      assert.is_truthy(r.code:match("^L%d%d%d$"), r.code .. " shape")
      assert.is_nil(seen[r.code], r.code .. " duplicated")
      seen[r.code] = true
      assert.is_true(prev < r.code, r.code .. " out of order")
      prev = r.code
    end
  end)

  it("gives every rule a name, severity and summary", function()
    for _, r in ipairs(rules.all()) do
      assert.is_true(#r.name > 0, r.code .. " has a name")
      assert.is_true(
        r.severity == "error" or r.severity == "warning",
        r.code .. " severity"
      )
      assert.is_true(#r.summary > 0, r.code .. " has a summary")
      assert.is_true(type(r.fixable) == "boolean", r.code .. " fixable flag")
    end
  end)

  it("flags L006 (float-eq-comparison) as an error", function()
    for _, r in ipairs(rules.all()) do
      if r.code == "L006" then
        assert.equals("error", r.severity)
      end
    end
  end)

  it("caches per session and reset() clears the cache", function()
    local first = rules.all()
    assert.equals(first, rules.all())
    rules.reset()
    rules.all() -- repopulates without error
  end)
end)

describe("telescope-m1.rules runtime catalogue (needs m1-lint --rules)", function()
  before_each(function()
    rules.reset()
  end)

  it("consumes the binary's catalogue: every binary rule appears in all()", function()
    local catalogue = rules.binary_catalogue()
    if not catalogue then
      pending("m1-lint with --rules not on $PATH")
      return
    end
    local by_code = {}
    for _, r in ipairs(rules.all()) do
      by_code[r.code] = r
    end
    for code, b in pairs(catalogue) do
      local got = by_code[code]
      assert.is_not_nil(got, code .. " missing from all()")
      assert.equals(b.name, got.name, code .. " name")
      assert.equals(b.fixable or false, got.fixable, code .. " fixability")
      -- v2 catalogues carry severity/summary; they must flow through verbatim.
      if b.severity then
        assert.equals(b.severity, got.severity, code .. " severity")
      end
      if b.summary then
        assert.equals(b.summary, got.summary, code .. " summary")
      end
    end
  end)
end)

-- Offline catalogue-parsing cases (from #15): deterministic, no binary needed.
describe("telescope-m1.rules.parse_catalogue", function()
  local V2 = vim.json.encode({
    version = 2,
    rules = {
      {
        code = "L006",
        name = "float-eq-comparison",
        severity = "error",
        fixable = false,
        summary = "float compared with an equality operator",
      },
      {
        code = "L099",
        name = "future-rule",
        severity = "deprecation",
        fixable = true,
        summary = "a severity this plugin has never heard of",
      },
    },
  })
  local V1 = vim.json.encode({
    version = 1,
    rules = {
      { code = "L002", name = "trailing-whitespace", fixable = true },
      { code = "L012", name = "unused-local", fixable = false },
    },
  })

  it("parses a v2 catalogue with all fields", function()
    local parsed = rules.parse_catalogue(V2)
    assert.is_not_nil(parsed)
    assert.same({
      name = "float-eq-comparison",
      severity = "error",
      fixable = false,
      summary = "float compared with an equality operator",
    }, parsed.L006)
  end)

  it("keeps unknown future severities as-is", function()
    local parsed = rules.parse_catalogue(V2)
    assert.equals("deprecation", parsed.L099.severity)
    -- And the picker presentation degrades instead of erroring.
    assert.equals("DiagnosticInfo", rules.severity_hl("deprecation"))
    assert.equals("depre", rules.severity_label("deprecation"))
  end)

  it("parses a v1 catalogue (no severity/summary fields)", function()
    local parsed = rules.parse_catalogue(V1)
    assert.is_not_nil(parsed)
    assert.equals("trailing-whitespace", parsed.L002.name)
    assert.is_nil(parsed.L002.severity, "v1 carries no severity; all() backfills")
  end)

  it("returns nil for garbage", function()
    assert.is_nil(rules.parse_catalogue(nil))
    assert.is_nil(rules.parse_catalogue(""))
    assert.is_nil(rules.parse_catalogue("not json"))
    assert.is_nil(rules.parse_catalogue("{}"))
  end)

  it("maps known severities to their highlight groups and labels", function()
    assert.equals("DiagnosticError", rules.severity_hl("error"))
    assert.equals("DiagnosticWarn", rules.severity_hl("warning"))
    assert.equals("error", rules.severity_label("error"))
    assert.equals("warn", rules.severity_label("warning"))
    assert.equals("?", rules.severity_label(nil))
  end)
end)
