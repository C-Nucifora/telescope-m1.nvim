--- Tests for the m1-typecheck T-code catalogue + picker.
---
--- Mirrors rules_spec.lua (the lint sync spec): the catalogue is read from the
--- m1-typecheck binary at runtime, so a newer m1-typecheck adding T-codes must
--- NOT fail this suite — but the offline fallback table must keep pace with the
--- released binary (a red spec here after a typecheck release is the sync
--- contract working, and belongs in the same release cascade).
local tc = require("telescope-m1.typecheck_rules")
local picker = require("telescope-m1.pickers.typecheck_rules")

describe("telescope-m1.typecheck_rules", function()
  before_each(function()
    tc.reset()
  end)

  it("lists T-codes in code order with unique codes", function()
    local all = tc.all()
    local catalogue = tc.binary_catalogue()
    if catalogue then
      local n = 0
      for _ in pairs(catalogue) do
        n = n + 1
      end
      assert.equals(n, #all, "all() mirrors the binary catalogue")
    else
      assert.is_true(#all >= 50, "fallback table regressed: " .. #all)
    end
    local seen = {}
    local prev = ""
    for _, r in ipairs(all) do
      assert.is_truthy(r.code:match("^T%d%d%d$"), r.code .. " shape")
      assert.is_true(#r.name > 0, r.code .. " has a name")
      assert.is_nil(seen[r.code], r.code .. " duplicated")
      seen[r.code] = true
      assert.is_true(prev < r.code, r.code .. " out of order")
      prev = r.code
    end
  end)

  it("fallback table covers T001..T110 endpoints", function()
    local by_code = {}
    for _, r in ipairs(tc.fallback_rules) do
      by_code[r.code] = r
    end
    assert.equals("unresolved-reference", (by_code.T001 or {}).name)
    assert.equals("dbc-signal-accessor-type", (by_code.T110 or {}).name)
    -- T107 dbc-init-missing shipped in m1-typecheck (AV-M1 escape); a spot check
    -- that a recently-added code is present offline.
    assert.equals("dbc-init-missing", (by_code.T107 or {}).name)
  end)

  it("caches per session and reset() clears the cache", function()
    local first = tc.all()
    assert.equals(first, tc.all())
    tc.reset()
    tc.all() -- repopulates without error
  end)
end)

describe("telescope-m1.typecheck_rules sync (needs m1-typecheck --rules)", function()
  before_each(function()
    tc.reset()
  end)

  it("the fallback table covers every T-code the binary defines", function()
    local catalogue = tc.binary_catalogue()
    if not catalogue then
      pending("m1-typecheck with --rules not on $PATH")
      return
    end
    local in_fallback = {}
    for _, r in ipairs(tc.fallback_rules) do
      in_fallback[r.code] = r
    end
    for code, b in pairs(catalogue) do
      local fb = in_fallback[code]
      assert.is_not_nil(fb, code .. " missing from M.fallback_rules")
      assert.equals(b.name, fb.name, code .. " fallback name")
    end
  end)

  it("every binary T-code appears in all()", function()
    local catalogue = tc.binary_catalogue()
    if not catalogue then
      pending("m1-typecheck with --rules not on $PATH")
      return
    end
    local by_code = {}
    for _, r in ipairs(tc.all()) do
      by_code[r.code] = r
    end
    for code, b in pairs(catalogue) do
      assert.is_not_nil(by_code[code], code .. " missing from all()")
      assert.equals(b.name, by_code[code].name, code .. " name")
    end
  end)
end)

describe("telescope-m1.typecheck_rules.parse_catalogue", function()
  local V1 = vim.json.encode({
    version = 1,
    rules = {
      { code = "T001", name = "unresolved-reference" },
      { code = "T031", name = "unresolved-assignment-target" },
    },
  })

  it("parses a v1 catalogue (code + name)", function()
    local parsed = tc.parse_catalogue(V1)
    assert.is_not_nil(parsed)
    assert.equals("unresolved-reference", parsed.T001.name)
    assert.equals("unresolved-assignment-target", parsed.T031.name)
  end)

  it("returns nil for garbage", function()
    assert.is_nil(tc.parse_catalogue(nil))
    assert.is_nil(tc.parse_catalogue(""))
    assert.is_nil(tc.parse_catalogue("not json"))
    assert.is_nil(tc.parse_catalogue("{}"))
  end)

  it(
    "docs_url_for resolves to the how-it-works section (no per-rule anchor)",
    function()
      assert.equals(tc.docs_url, tc.docs_url_for({ code = "T031", name = "x" }))
      assert.equals(tc.docs_url, tc.docs_url_for(nil))
    end
  )
end)

describe("typecheck_rules picker: make_entry", function()
  local entry_display = require("telescope.pickers.entry_display")

  local function make_displayer()
    return entry_display.create({
      separator = "  ",
      items = { { width = 5 }, { remaining = true } },
    })
  end

  local function build_entry(rule, displayer)
    return picker._make_entry(displayer or make_displayer())(rule)
  end

  it("ordinal is 'code name' and value is the raw rule", function()
    local rule = { code = "T031", name = "unresolved-assignment-target" }
    local entry = build_entry(rule)
    assert.equals("T031 unresolved-assignment-target", entry.ordinal)
    assert.equals("T031", entry.value.code)
    assert.is_function(entry.display)
  end)

  it("display passes code and name to the displayer", function()
    local captured
    local function fake_displayer(args)
      captured = args
      return "", {}
    end
    local rule = { code = "T042", name = "dbc-signal-range" }
    build_entry(rule, fake_displayer).display()
    assert.equals("T042", captured[1][1])
    assert.equals("dbc-signal-range", captured[2][1])
  end)
end)

describe("typecheck_rules picker: yank handler", function()
  it("setreg receives the T-code for both + and default registers", function()
    local regs = {}
    local orig_setreg = vim.fn.setreg
    local orig_notify = vim.notify
    vim.fn.setreg = function(reg, val)
      regs[reg] = val
    end
    vim.notify = function() end

    picker._yank_code({ value = { code = "T031" } })

    vim.fn.setreg = orig_setreg
    vim.notify = orig_notify

    assert.equals("T031", regs["+"])
    assert.equals("T031", regs['"'])
  end)

  it("is a no-op when no entry is selected", function()
    local called = false
    local orig_setreg = vim.fn.setreg
    vim.fn.setreg = function()
      called = true
    end
    picker._yank_code(nil)
    vim.fn.setreg = orig_setreg
    assert.is_false(called)
  end)
end)
