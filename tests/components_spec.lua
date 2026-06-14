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

-- ─── project_edit / select_edit: component attribute editors (#45) ──────────
--
-- We drive the REAL project_edit / select_edit handlers (exposed as
-- components._project_edit / ._select_edit) with stubbed action_state,
-- actions.close, the nvim-m1 project module and vim.ui.select, capturing which
-- nvim-m1.project function is dispatched with which (cfg, component) args.

--- Run a components handler with `entry` selected and `project` standing in for
--- `require("nvim-m1.project")`. Returns the captured dispatch + notifications.
---@param handler fun(bufnr: integer)
---@param entry table?
---@param project table  fake nvim-m1.project (function name -> fn)
---@param ui_choice? string|nil  what vim.ui.select picks (for select_edit)
local function run_edit(handler, entry, project, ui_choice)
  local dispatched = {} -- list of { fn = name, cfg = ..., component = ... }
  local notifications = {}
  local offered_items = nil -- labels passed to vim.ui.select

  local orig_get_selected = action_state.get_selected_entry
  local orig_close = actions.close
  local orig_notify = vim.notify
  local orig_ui_select = vim.ui.select
  local orig_require = _G.require

  -- Wrap each fake project fn so we record the dispatch.
  local wrapped = {}
  for name, fn in pairs(project) do
    wrapped[name] = function(cfg, component)
      dispatched[#dispatched + 1] = { fn = name, cfg = cfg, component = component }
      if fn then
        fn(cfg, component)
      end
    end
  end

  action_state.get_selected_entry = function()
    return entry
  end
  actions.close = function() end
  vim.notify = function(msg, level)
    notifications[#notifications + 1] = { msg = msg, level = level }
  end
  vim.ui.select = function(items, _opts, on_choice)
    -- record the offered labels so the menu can be asserted
    offered_items = items
    on_choice(ui_choice)
  end
  -- Intercept require so the handler's `require("nvim-m1")` /
  -- `require("nvim-m1.project")` resolve to our fakes, untouched for the rest.
  _G.require = function(mod)
    if mod == "nvim-m1" then
      return { config = { project_path = "/fake" } }
    elseif mod == "nvim-m1.project" then
      return wrapped
    end
    return orig_require(mod)
  end

  local ok, err = pcall(handler, 0)

  action_state.get_selected_entry = orig_get_selected
  actions.close = orig_close
  vim.notify = orig_notify
  vim.ui.select = orig_ui_select
  _G.require = orig_require

  assert.is_true(ok, "handler errored: " .. tostring(err))
  return {
    dispatched = dispatched,
    notifications = notifications,
    offered_items = offered_items,
  }
end

describe("components picker: project_edit dispatch (#45)", function()
  local entry = { value = { name = "Root.Vehicle.Speed" } }
  -- A fake nvim-m1.project that exposes every editor wired by the picker.
  local full_project = {
    set_security = false,
    set_type = false,
    set_unit = false,
    rename_component = false,
    delete_component = false,
    set_quantity = false,
    set_validation = false,
    set_format = false,
    set_dps = false,
    set_display_range = false,
    add_tag = false,
    remove_tag = false,
  }

  it("dispatches set_quantity with the selected component name", function()
    local result =
      run_edit(components._project_edit("set_quantity"), entry, full_project)
    assert.equals(1, #result.dispatched)
    assert.equals("set_quantity", result.dispatched[1].fn)
    assert.equals("Root.Vehicle.Speed", result.dispatched[1].component)
    assert.equals("/fake", result.dispatched[1].cfg.project_path)
  end)

  it("degrades with a WARN when nvim-m1 lacks the requested editor", function()
    -- An OLDER nvim-m1 with none of the #61 editors present.
    local old_project = { set_security = false }
    local result =
      run_edit(components._project_edit("set_validation"), entry, old_project)
    assert.equals(0, #result.dispatched, "must not dispatch a missing function")
    assert.is_true(#result.notifications > 0, "should notify about the gap")
    assert.equals(vim.log.levels.WARN, result.notifications[1].level)
  end)
end)

describe("components picker: select_edit attribute menu (#45)", function()
  local entry = { value = { name = "Root.Vehicle.Speed" } }
  local full_project = {
    set_quantity = false,
    set_validation = false,
    set_format = false,
    set_dps = false,
    set_display_range = false,
    add_tag = false,
    remove_tag = false,
  }

  -- Every attribute the detail card surfaces must be reachable from the menu,
  -- mapped to its nvim-m1.project editor (the parity the finding is about).
  local expected = {
    Quantity = "set_quantity",
    Validation = "set_validation",
    Format = "set_format",
    ["Decimal places"] = "set_dps",
    ["Display range"] = "set_display_range",
    ["Add tag"] = "add_tag",
    ["Remove tag"] = "remove_tag",
  }

  for label, fn in pairs(expected) do
    it("'" .. label .. "' dispatches " .. fn, function()
      local result = run_edit(components._select_edit, entry, full_project, label)
      assert.equals(1, #result.dispatched, "exactly one editor should run")
      assert.equals(fn, result.dispatched[1].fn)
      assert.equals("Root.Vehicle.Speed", result.dispatched[1].component)
    end)
  end

  it("offers all seven extra attributes in the menu", function()
    local result = run_edit(components._select_edit, entry, full_project, nil)
    local offered = result.offered_items
    assert.equals(7, #offered)
    -- the menu labels must be exactly the EXTRA_EDITS labels, in order
    for i, e in ipairs(components._EXTRA_EDITS) do
      assert.equals(e.label, offered[i])
    end
  end)

  it("does nothing when the menu is dismissed", function()
    local result = run_edit(components._select_edit, entry, full_project, nil)
    assert.equals(0, #result.dispatched)
  end)
end)

-- The nil/empty-filename guard is verified behaviourally above: the nil and
-- empty-string cases assert edit_called == false and a WARN notification, which
-- holds regardless of how the guard is spelled in the source.
