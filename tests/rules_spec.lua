local rules = require("telescope-m1.rules")

-- A v2 catalogue sample (m1-lint >= catalogue v2: severity + summary, #118).
local V2 = vim.json.encode({
  version = 2,
  rules = {
    {
      code = "L001",
      name = "line-too-long",
      severity = "warning",
      fixable = false,
      summary = "line exceeds the configured maximum length",
    },
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

-- A v1 catalogue sample (older m1-lint: code/name/fixable only).
local V1 = vim.json.encode({
  version = 1,
  rules = {
    { code = "L002", name = "trailing-whitespace", fixable = true },
    { code = "L012", name = "unused-local", fixable = false },
  },
})

describe("telescope-m1.rules.parse_catalogue", function()
  it("parses a v2 catalogue with all fields", function()
    local parsed = rules.parse_catalogue(V2)
    assert.is_not_nil(parsed)
    assert.equals(3, #parsed)
    assert.same({
      code = "L006",
      name = "float-eq-comparison",
      severity = "error",
      fixable = false,
      summary = "float compared with an equality operator",
    }, parsed[2])
  end)

  it("keeps unknown future severities as-is", function()
    local parsed = rules.parse_catalogue(V2)
    assert.equals("deprecation", parsed[3].severity)
    assert.is_true(parsed[3].fixable)
  end)

  it("synthesises severity and summary for a v1 catalogue", function()
    local parsed = rules.parse_catalogue(V1)
    assert.is_not_nil(parsed)
    assert.equals(2, #parsed)
    assert.equals("warning", parsed[1].severity)
    assert.equals("trailing whitespace", parsed[1].summary)
    assert.is_true(parsed[1].fixable)
    assert.equals("unused local", parsed[2].summary)
  end)

  it("rejects garbage, empty and rule-less output", function()
    assert.is_nil(rules.parse_catalogue(nil))
    assert.is_nil(rules.parse_catalogue(""))
    assert.is_nil(rules.parse_catalogue("m1-lint: unknown flag --rules"))
    assert.is_nil(rules.parse_catalogue("{}"))
    assert.is_nil(rules.parse_catalogue('{"version":2,"rules":[]}'))
  end)
end)

describe("telescope-m1.rules severity presentation", function()
  it("maps the known severities to diagnostic highlights", function()
    assert.equals("DiagnosticError", rules.severity_hl("error"))
    assert.equals("DiagnosticWarn", rules.severity_hl("warning"))
  end)

  it("degrades unknown severities to a default highlight", function()
    assert.equals("DiagnosticInfo", rules.severity_hl("deprecation"))
    assert.equals("DiagnosticInfo", rules.severity_hl(nil))
  end)

  it("labels severities compactly for the picker column", function()
    assert.equals("error", rules.severity_label("error"))
    assert.equals("warn", rules.severity_label("warning"))
    assert.equals("depre", rules.severity_label("deprecation"))
    assert.equals("?", rules.severity_label(nil))
  end)
end)

describe("telescope-m1.rules.all", function()
  before_each(function()
    rules._invalidate()
  end)

  it("returns a well-formed registry whatever the source", function()
    local all = rules.all()
    assert.is_true(#all > 0)
    local seen = {}
    for _, r in ipairs(all) do
      assert.is_truthy(r.code:match("^L%d+$"), tostring(r.code) .. " code shape")
      assert.is_nil(seen[r.code], r.code .. " duplicated")
      seen[r.code] = true
      assert.is_true(#r.name > 0, r.code .. " has a name")
      assert.is_true(
        type(r.severity) == "string" and #r.severity > 0,
        r.code .. " has a severity"
      )
      assert.is_true(#r.summary > 0, r.code .. " has a summary")
      assert.equals("boolean", type(r.fixable), r.code .. " fixable is boolean")
    end
  end)

  it("caches the registry for the session", function()
    local first = rules.all()
    assert.equals(first, rules.all())
    rules._invalidate()
    assert.is_not_nil(rules.all())
  end)

  it("reflects the binary's catalogue when one is available", function()
    local catalogue = rules.binary_catalogue()
    if not catalogue then
      pending("m1-lint not resolvable (nvim-m1 bundle or $PATH)")
      return
    end
    -- all() must be exactly the binary's catalogue: a new lint release shows
    -- up here with zero changes to this plugin (#14's acceptance criterion).
    assert.same(catalogue, rules.all())
  end)
end)
