local rules = require("telescope-m1.rules")

-- Schema-shape assertions only (#14): the catalogue is read from the m1-lint
-- binary at runtime, so a newer m1-lint adding rules must NOT fail this suite.
describe("telescope-m1.rules", function()
  before_each(function()
    rules.reset()
  end)

  it("lists rules in code order with unique codes", function()
    local all = rules.all()
    assert.is_true(#all >= 24, "expected at least the v0.14 rule set, got " .. #all)
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
