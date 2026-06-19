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
      assert.is_true(#all >= 27, "fallback table regressed: " .. #all)
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

  -- The fallback table is the catalogue when no m1-lint binary can be
  -- resolved at all. It must keep pace with the released m1-lint, so a rule
  -- that ships default-on (e.g. L028 brace-style, m1-lint v0.20.0) is still
  -- offered by the lint_rules picker offline. Asserting the fallback table
  -- directly (not all(), which is binary-driven when the binary is present)
  -- catches the drift even on a runner that has m1-lint installed.
  it("fallback table includes L028 (brace-style, default-on)", function()
    local by_code = {}
    for _, r in ipairs(rules.fallback_rules) do
      by_code[r.code] = r
    end
    local l028 = by_code.L028
    assert.is_not_nil(l028, "fallback table missing L028 (brace-style)")
    assert.equals("brace-style", l028.name)
    assert.equals("warning", l028.severity)
    assert.equals(false, l028.fixable)
    assert.is_true(#l028.summary > 0, "L028 has a summary")
  end)

  -- L029 indentation-depth shipped with m1-lint v0.21.0; like L028 it must be
  -- in the offline fallback so the picker still offers it without a binary.
  it("fallback table includes L029 (indentation-depth, m1-lint v0.21.0)", function()
    local by_code = {}
    for _, r in ipairs(rules.fallback_rules) do
      by_code[r.code] = r
    end
    local l029 = by_code.L029
    assert.is_not_nil(l029, "fallback table missing L029 (indentation-depth)")
    assert.equals("indentation-depth", l029.name)
    assert.equals("warning", l029.severity)
    assert.equals(false, l029.fixable)
    assert.is_true(#l029.summary > 0, "L029 has a summary")
  end)

  -- L030 clause-parentheses shipped with m1-lint v0.23.0; like L028/L029 it
  -- must be in the offline fallback so the picker still offers it without a
  -- binary.
  it("fallback table includes L030 (clause-parentheses, m1-lint v0.23.0)", function()
    local by_code = {}
    for _, r in ipairs(rules.fallback_rules) do
      by_code[r.code] = r
    end
    local l030 = by_code.L030
    assert.is_not_nil(l030, "fallback table missing L030 (clause-parentheses)")
    assert.equals("clause-parentheses", l030.name)
    assert.equals("warning", l030.severity)
    assert.equals(true, l030.fixable)
    assert.is_true(#l030.summary > 0, "L030 has a summary")
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

  -- The fallback table (used offline) must itself cover every binary rule, not
  -- just all() (which is binary-driven when the binary is present and so would
  -- mask a stale fallback). This is the guard that prevents a future m1-lint
  -- rule from silently leaving M.fallback_rules behind.
  it("fallback table covers every rule the binary defines", function()
    local catalogue = rules.binary_catalogue()
    if not catalogue then
      pending("m1-lint with --rules not on $PATH")
      return
    end
    local in_fallback = {}
    for _, r in ipairs(rules.fallback_rules) do
      in_fallback[r.code] = r
    end
    for code, b in pairs(catalogue) do
      local fb = in_fallback[code]
      assert.is_not_nil(fb, code .. " missing from M.fallback_rules")
      assert.equals(b.name, fb.name, code .. " fallback name")
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

  -- #34: deep-link each rule to its README heading anchor. m1-lint (#148)
  -- publishes `### <name> (<CODE>)` headings whose GitHub slug is
  -- `<name>-<code-lowercased>`, so the picker must build that exact fragment.
  it("docs_url_for deep-links the selected rule's README anchor", function()
    assert.equals(
      "https://github.com/C-Nucifora/m1-lint#line-too-long-l001",
      rules.docs_url_for({ name = "line-too-long", code = "L001" })
    )
  end)

  it("docs_url_for falls back to the section anchor without a name/code", function()
    assert.equals(rules.docs_url, rules.docs_url_for(nil))
    assert.equals(rules.docs_url, rules.docs_url_for({ code = "L001" }))
  end)
end)
