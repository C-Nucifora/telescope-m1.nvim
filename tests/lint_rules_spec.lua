--- Tests for telescope-m1/pickers/lint_rules.lua
---
--- Exercises:
---   * make_entry / entry_maker: ordinal and display fields are correct
---   * ignore_in_config: delegates to ignore.merge_ignore and writes the file
---   * ignore_in_config: "already_ignored" path suppresses write
---   * ignore_in_config: "fallback" path triggers a WARN notify
---   * yank handler: setreg receives the correct code (tested via the
---     action_state mock pattern used by the existing specs)
local rules = require("telescope-m1.rules")
local lint_rules = require("telescope-m1.pickers.lint_rules")

-- ─── helpers ───────────────────────────────────────────────────────────────

local function sample_rule(overrides)
  return vim.tbl_extend("force", {
    code = "L006",
    name = "float-eq-comparison",
    severity = "error",
    fixable = false,
    summary = "float compared with an equality operator",
  }, overrides or {})
end

-- ─── entry_maker ───────────────────────────────────────────────────────────

describe("lint_rules picker: make_entry", function()
  -- We exercise the REAL make_entry (exposed as lint_rules._make_entry) by
  -- building the same displayer the picker creates at runtime and calling the
  -- entry_maker it returns — exactly as component_preview_spec exercises
  -- render_card directly. A regression in the source now fails this spec.

  local entry_display = require("telescope.pickers.entry_display")

  local function make_displayer()
    return entry_display.create({
      separator = "  ",
      items = {
        { width = 5 },
        { width = 24 },
        { width = 5 },
        { width = 3 },
        { remaining = true },
      },
    })
  end

  -- Drive the real entry_maker. Pass an optional displayer override so the
  -- "display args" tests can intercept the displayer call without a window.
  local function build_entry(rule, displayer)
    return lint_rules._make_entry(displayer or make_displayer())(rule)
  end

  it("ordinal is 'code name'", function()
    local rule = sample_rule()
    local entry = build_entry(rule)
    assert.equals("L006 float-eq-comparison", entry.ordinal)
  end)

  it("value is the raw rule table", function()
    local rule = sample_rule()
    local entry = build_entry(rule)
    assert.equals("L006", entry.value.code)
    assert.equals("float-eq-comparison", entry.value.name)
    assert.equals("error", entry.value.severity)
    assert.is_false(entry.value.fixable)
  end)

  it("entry has a display function for an error-severity, non-fixable rule", function()
    local entry = build_entry(sample_rule())
    assert.is_function(entry.display)
  end)

  it("entry has a display function for a warning-severity, fixable rule", function()
    local rule = sample_rule({ code = "L002", severity = "warning", fixable = true })
    local entry = build_entry(rule)
    assert.is_function(entry.display)
  end)

  it("entry has a display function for an unknown future severity", function()
    local rule = sample_rule({ severity = "deprecation" })
    local entry = build_entry(rule)
    assert.is_function(entry.display)
  end)

  it("display args include severity label and highlight from rules module", function()
    -- Instead of invoking the displayer (which needs a live window), verify
    -- that the arguments the REAL display function passes to it are assembled
    -- correctly by intercepting the displayer call.
    local captured_args
    local function fake_displayer(args)
      captured_args = args
      return "", {}
    end
    local rule = sample_rule({ severity = "error", fixable = false })
    local entry = build_entry(rule, fake_displayer)
    entry.display()
    assert.is_not_nil(captured_args)
    -- Slot 0 is code.
    assert.equals("L006", captured_args[1][1])
    -- Slot 1 is name.
    assert.equals("float-eq-comparison", captured_args[2][1])
    -- Slot 2 is the severity pair: label + highlight.
    assert.equals(rules.severity_label("error"), captured_args[3][1])
    assert.equals(rules.severity_hl("error"), captured_args[3][2])
    -- Slot 3 is fixable text: empty for non-fixable.
    assert.equals("", captured_args[4][1])
  end)

  it("display args use 'fix' text for a fixable rule", function()
    local captured_args
    local function fake_displayer(args)
      captured_args = args
      return "", {}
    end
    local rule = sample_rule({ code = "L002", severity = "warning", fixable = true })
    local entry = build_entry(rule, fake_displayer)
    entry.display()
    assert.equals("fix", captured_args[4][1])
  end)

  it("ordinal contains both code and name for every fallback rule", function()
    for _, r in ipairs(rules.all()) do
      local entry = build_entry(r)
      assert.is_truthy(
        entry.ordinal:find(r.code, 1, true),
        r.code .. " missing from ordinal"
      )
      assert.is_truthy(
        entry.ordinal:find(r.name, 1, true),
        r.name .. " missing from ordinal"
      )
    end
  end)
end)

-- ─── ignore_in_config ──────────────────────────────────────────────────────

describe("lint_rules picker: ignore_in_config", function()
  -- ignore_in_config is private-by-convention inside the picker module, exposed
  -- for tests as lint_rules._ignore_in_config. We drive the REAL function with
  -- controlled filesystem state (same approach as component_preview_spec, which
  -- directly calls preview.render_card) and verify the outward effects
  -- (writefile calls, notify messages).

  -- Capture and restore stubs in after_each.
  local orig_getcwd
  local orig_buf_get_name
  local orig_fs_find
  local orig_filereadable
  local orig_readfile
  local orig_writefile
  local orig_notify

  before_each(function()
    orig_getcwd = vim.fn.getcwd
    orig_buf_get_name = vim.api.nvim_buf_get_name
    orig_fs_find = vim.fs.find
    orig_filereadable = vim.fn.filereadable
    orig_readfile = vim.fn.readfile
    orig_writefile = vim.fn.writefile
    orig_notify = vim.notify
  end)

  after_each(function()
    vim.fn.getcwd = orig_getcwd
    vim.api.nvim_buf_get_name = orig_buf_get_name
    vim.fs.find = orig_fs_find
    vim.fn.filereadable = orig_filereadable
    vim.fn.readfile = orig_readfile
    vim.fn.writefile = orig_writefile
    vim.notify = orig_notify
  end)

  -- Stub the filesystem + notify so the REAL ignore_in_config (exposed as
  -- lint_rules._ignore_in_config) runs its decision tree without touching the
  -- disk, and capture the outward effects (writefile / notify). The function
  -- under test is the production source — no copy.
  local function run_ignore_in_config(code, existing_lines, found_path)
    local written_lines
    local written_path
    local notifications = {}

    vim.fn.getcwd = function()
      return "/fake/cwd"
    end
    vim.api.nvim_buf_get_name = function()
      return ""
    end
    vim.fs.find = function()
      return found_path and { found_path } or {}
    end
    vim.fn.filereadable = function()
      return (existing_lines ~= nil) and 1 or 0
    end
    vim.fn.readfile = function()
      return existing_lines or {}
    end
    vim.fn.writefile = function(lines, path)
      written_lines = vim.deepcopy(lines)
      written_path = path
      return 0
    end
    vim.notify = function(msg, level)
      notifications[#notifications + 1] = { msg = msg, level = level }
    end

    lint_rules._ignore_in_config(code)

    return {
      written_lines = written_lines,
      written_path = written_path,
      notifications = notifications,
    }
  end

  it("creates a .m1lint.toml when no file exists", function()
    local result = run_ignore_in_config("L004", nil, nil)
    assert.is_not_nil(result.written_lines, "file must be written")
    local content = table.concat(result.written_lines, "\n")
    assert.is_truthy(content:find("L004", 1, true))
    assert.is_truthy(content:find("%[lint%]"))
    assert.equals(1, #result.notifications)
  end)

  it("merges code into an existing single-line ignore array", function()
    local existing = { "[lint]", 'ignore = ["L001"]' }
    local result = run_ignore_in_config("L004", existing, "/fake/cwd/.m1lint.toml")
    assert.is_not_nil(result.written_lines)
    local content = table.concat(result.written_lines, "\n")
    assert.is_truthy(content:find('"L001"', 1, true))
    assert.is_truthy(content:find('"L004"', 1, true))
  end)

  it("skips writefile when the code is already ignored", function()
    local existing = { "[lint]", 'ignore = ["L004"]' }
    local result = run_ignore_in_config("L004", existing, "/fake/cwd/.m1lint.toml")
    assert.is_nil(
      result.written_lines,
      "writefile must NOT be called for already_ignored"
    )
    assert.equals(1, #result.notifications)
    assert.equals(vim.log.levels.INFO, result.notifications[1].level)
    assert.is_truthy(result.notifications[1].msg:find("already ignored", 1, true))
  end)

  it("emits a WARN notification for the multi-line-array fallback path", function()
    local existing = {
      "[lint]",
      "ignore = [",
      '  "L001",',
      "]",
    }
    local result = run_ignore_in_config("L004", existing, "/fake/cwd/.m1lint.toml")
    assert.is_not_nil(result.written_lines)
    assert.equals(1, #result.notifications)
    assert.equals(vim.log.levels.WARN, result.notifications[1].level)
    assert.is_truthy(result.notifications[1].msg:find("multi-line array", 1, true))
  end)

  it("uses the found .m1lint.toml path, not a synthesized one", function()
    local existing = { "[lint]", 'ignore = ["L001"]' }
    local found = "/project/root/.m1lint.toml"
    local result = run_ignore_in_config("L004", existing, found)
    assert.equals(found, result.written_path)
  end)

  it("synthesises a fallback path under cwd when no file is found", function()
    local result = run_ignore_in_config("L004", nil, nil)
    assert.equals("/fake/cwd/.m1lint.toml", result.written_path)
  end)
end)

-- ─── yank handler (setreg contract) ────────────────────────────────────────

describe("lint_rules picker: yank handler registers", function()
  -- The <C-y> handler (the REAL lint_rules._yank_code) calls
  -- vim.fn.setreg("+", entry.value.code) and the unnamed register.  We verify
  -- both registers receive the correct code.

  it("setreg receives the rule code for both + and default registers", function()
    local regs = {}
    local orig_setreg = vim.fn.setreg
    local orig_notify = vim.notify

    vim.fn.setreg = function(reg, val)
      regs[reg] = val
    end
    vim.notify = function() end

    lint_rules._yank_code({ value = { code = "L006" } })

    vim.fn.setreg = orig_setreg
    vim.notify = orig_notify

    assert.equals("L006", regs["+"])
    assert.equals("L006", regs['"'])
  end)

  it("yank handler copies the exact code from the entry value", function()
    local yanked = {}
    local orig_setreg = vim.fn.setreg
    local orig_notify = vim.notify
    vim.fn.setreg = function(_, val)
      yanked[#yanked + 1] = val
    end
    vim.notify = function() end

    local codes = { "L001", "L006", "L027" }
    for _, code in ipairs(codes) do
      lint_rules._yank_code({ value = { code = code } })
    end

    vim.fn.setreg = orig_setreg
    vim.notify = orig_notify

    assert.same({ "L001", "L001", "L006", "L006", "L027", "L027" }, yanked)
  end)

  it("is a no-op when no entry is selected (nil entry)", function()
    local called = false
    local orig_setreg = vim.fn.setreg
    local orig_notify = vim.notify
    vim.fn.setreg = function()
      called = true
    end
    vim.notify = function() end

    lint_rules._yank_code(nil)

    vim.fn.setreg = orig_setreg
    vim.notify = orig_notify

    assert.is_false(called, "setreg must not be called for a nil entry")
  end)
end)
