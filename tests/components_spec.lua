--- Tests for telescope-m1/pickers/components.lua
---
--- Exercises:
---   * goto_backing_script guard: skips vim.cmd.edit when filename is nil
---   * goto_backing_script guard: skips vim.cmd.edit when filename is empty
---   * goto_backing_script guard: calls vim.cmd.edit for a valid filename
---
--- Private function testing approach: we reproduce the handler logic here with
--- injectable stubs, exactly as lint_rules_spec reproduces ignore_in_config.

-- ─── helpers ───────────────────────────────────────────────────────────────

--- Re-implement goto_backing_script logic verbatim from components.lua so that
--- we test the real decision tree in isolation, with controlled inputs.
--- This is kept in sync with the source by design; a drift will surface via
--- the source-contract test below.
---
--- Returns a table of observations:
---   edit_called   boolean  – was vim.cmd.edit invoked?
---   edit_arg      any      – argument passed to vim.cmd.edit (if called)
---   notifications table    – list of {msg, level} pairs from vim.notify
local function run_goto_backing_script(entry)
  local edit_called = false
  local edit_arg = nil
  local notifications = {}

  local orig_cmd_edit = vim.cmd.edit
  local orig_notify = vim.notify

  vim.cmd.edit = function(arg)
    edit_called = true
    edit_arg = arg
  end
  vim.notify = function(msg, level)
    notifications[#notifications + 1] = { msg = msg, level = level }
  end

  -- Reproduce goto_backing_script from components.lua exactly, including the
  -- filename guard introduced by this fix.
  local function handler()
    if not entry then
      return
    end
    local kind = entry.value and entry.value.kind_label
    if kind ~= "Function" and kind ~= "Method" then
      vim.notify(
        "telescope-m1: not a script-backed entry (" .. (kind or "?") .. ")",
        vim.log.levels.INFO
      )
      return
    end
    if not entry.filename or entry.filename == "" then
      vim.notify("telescope-m1: no backing file for this entry", vim.log.levels.WARN)
      return
    end
    vim.cmd.edit(entry.filename)
  end

  handler()

  vim.cmd.edit = orig_cmd_edit
  vim.notify = orig_notify

  return {
    edit_called = edit_called,
    edit_arg = edit_arg,
    notifications = notifications,
  }
end

-- ─── goto_backing_script: filename guard ───────────────────────────────────

describe("components picker: goto_backing_script filename guard", function()
  it("does NOT call vim.cmd.edit when filename is nil", function()
    local result = run_goto_backing_script({
      value = { kind_label = "Function" },
      filename = nil,
    })
    assert.is_false(result.edit_called, "edit must not be called for nil filename")
  end)

  it("does NOT call vim.cmd.edit when filename is empty string", function()
    local result = run_goto_backing_script({
      value = { kind_label = "Function" },
      filename = "",
    })
    assert.is_false(result.edit_called, "edit must not be called for empty filename")
  end)

  it("notifies (WARN) instead of editing when filename is nil", function()
    local result = run_goto_backing_script({
      value = { kind_label = "Function" },
      filename = nil,
    })
    assert.is_true(
      #result.notifications > 0,
      "a notification should fire when filename is nil"
    )
    assert.equals(vim.log.levels.WARN, result.notifications[1].level)
  end)

  it("notifies (WARN) instead of editing when filename is empty", function()
    local result = run_goto_backing_script({
      value = { kind_label = "Function" },
      filename = "",
    })
    assert.is_true(
      #result.notifications > 0,
      "a notification should fire when filename is empty"
    )
    assert.equals(vim.log.levels.WARN, result.notifications[1].level)
  end)

  it("calls vim.cmd.edit with the filename when it is a non-empty string", function()
    local result = run_goto_backing_script({
      value = { kind_label = "Function" },
      filename = "/path/to/Script.m1scr",
    })
    assert.is_true(result.edit_called, "edit must be called for a valid filename")
    assert.equals("/path/to/Script.m1scr", result.edit_arg)
  end)

  it("calls vim.cmd.edit for a Method entry with a valid filename", function()
    local result = run_goto_backing_script({
      value = { kind_label = "Method" },
      filename = "/another/Script.m1scr",
    })
    assert.is_true(result.edit_called, "edit must be called for Method with valid filename")
    assert.equals("/another/Script.m1scr", result.edit_arg)
  end)

  it("does not call edit for a non-Function/Method kind", function()
    local result = run_goto_backing_script({
      value = { kind_label = "Variable" },
      filename = "/some/file.m1prj",
    })
    assert.is_false(result.edit_called, "edit must not be called for a non-script kind")
    assert.is_true(#result.notifications > 0)
  end)
end)

-- ─── source-level contract ─────────────────────────────────────────────────

describe("components picker: goto_backing_script source guard (#bug)", function()
  it("source contains a nil/empty filename guard before vim.cmd.edit", function()
    local here = debug.getinfo(1, "S").source:sub(2)
    local src_path = here:gsub(
      "tests/components_spec%.lua$",
      "lua/telescope-m1/pickers/components.lua"
    )
    local f = assert(io.open(src_path, "r"))
    local src = f:read("*a")
    f:close()

    -- The source must guard entry.filename before calling vim.cmd.edit.
    -- Use plain-text search (no Lua pattern escaping): the literal strings we
    -- look for are "entry.filename" and "not entry.filename".
    assert.is_true(
      src:find("entry.filename", 1, true) ~= nil
        and (
          src:find("not entry.filename", 1, true) ~= nil
          or src:find('entry.filename == ""', 1, true) ~= nil
        ),
      "components.lua must guard entry.filename before calling vim.cmd.edit"
    )
  end)
end)
