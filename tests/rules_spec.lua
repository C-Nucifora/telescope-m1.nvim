local rules = require("telescope-m1.rules")

describe("telescope-m1.rules", function()
  it("lists L001..L012 in order with unique codes", function()
    local all = rules.all()
    assert.equals(12, #all)
    for i, r in ipairs(all) do
      assert.equals(("L%03d"):format(i), r.code)
    end
  end)

  it("marks exactly the m1-lint-fixable rules as fixable", function()
    local fixable = {}
    for _, r in ipairs(rules.all()) do
      if r.fixable then
        fixable[r.code] = true
      end
    end
    -- Matches m1-lint's LintCode::fixable.
    assert.same(
      { L002 = true, L003 = true, L004 = true, L005 = true, L007 = true, L011 = true },
      fixable
    )
  end)

  it("gives every rule a name, severity and summary", function()
    for _, r in ipairs(rules.all()) do
      assert.is_true(#r.name > 0, r.code .. " has a name")
      assert.is_true(
        r.severity == "error" or r.severity == "warning",
        r.code .. " severity"
      )
      assert.is_true(#r.summary > 0, r.code .. " has a summary")
    end
  end)

  it("flags L006 as an error", function()
    for _, r in ipairs(rules.all()) do
      if r.code == "L006" then
        assert.equals("error", r.severity)
      end
    end
  end)
end)

describe("telescope-m1.rules sync with m1-lint (needs m1-lint --rules)", function()
  it("matches the binary's catalogue exactly (codes, names, fixability)", function()
    local catalogue = rules.binary_catalogue()
    if not catalogue then
      pending("m1-lint with --rules not on $PATH")
      return
    end

    -- Index the static table by code.
    local static = {}
    for _, r in ipairs(rules.all()) do
      static[r.code] = r
    end

    -- Every binary rule is represented, with matching name + fixability.
    for code, b in pairs(catalogue) do
      local s = static[code]
      assert.is_not_nil(
        s,
        "static table is missing "
          .. code
          .. " — run :h telescope-m1 and update rules.lua"
      )
      assert.equals(b.name, s.name, code .. " name drifted")
      assert.equals(b.fixable, s.fixable, code .. " fixability drifted")
    end

    -- And the static table has no rules the binary doesn't know about.
    for code in pairs(static) do
      assert.is_not_nil(catalogue[code], "static table has stale rule " .. code)
    end
  end)
end)
