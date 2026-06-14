--- Tests for telescope-m1/pickers/components.lua
---
--- Exercises:
---   * goto_backing_script guard: skips vim.cmd.edit when filename is nil
---   * goto_backing_script guard: skips vim.cmd.edit when filename is empty
---   * goto_backing_script guard: calls vim.cmd.edit for a valid filename
---
--- Private function testing approach: we drive the REAL handler (exposed as
--- components._goto_backing_script) with injectable stubs, exactly as
--- lint_rules_spec drives the real ignore_in_config.

-- ─── helpers ───────────────────────────────────────────────────────────────

local components = require("telescope-m1.pickers.components")
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

--- Run the REAL goto_backing_script from components.lua with `entry` as the
--- selected Telescope entry, capturing the outward effects. Stubs
--- action_state.get_selected_entry (the handler reads the selection itself),
--- actions.close, vim.cmd.edit and vim.notify so nothing touches a live UI.
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
  local orig_get_selected = action_state.get_selected_entry
  local orig_close = actions.close

  vim.cmd.edit = function(arg)
    edit_called = true
    edit_arg = arg
  end
  vim.notify = function(msg, level)
    notifications[#notifications + 1] = { msg = msg, level = level }
  end
  action_state.get_selected_entry = function()
    return entry
  end
  actions.close = function() end

  components._goto_backing_script(0) -- bufnr is only forwarded to actions.close

  vim.cmd.edit = orig_cmd_edit
  vim.notify = orig_notify
  action_state.get_selected_entry = orig_get_selected
  actions.close = orig_close

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
    assert.is_true(
      result.edit_called,
      "edit must be called for Method with valid filename"
    )
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

-- The nil/empty-filename guard is verified behaviourally above: the nil and
-- empty-string cases assert edit_called == false and a WARN notification, which
-- holds regardless of how the guard is spelled in the source.
