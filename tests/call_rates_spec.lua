--- Tests for telescope-m1/pickers/call_rates.lua
---
--- Exercises:
---   * rate_value(): "startup" label → "startup"; "100Hz" → "100"; "1000Hz" → "1000"
---   * entry array access: entry[1] is used (not entry.value) for rate labels
---   * nvim-m1 absent path: picker notifies and returns early (no error thrown)
---   * set_call_rate_for delegation: the <C-a> handler invokes
---     project.set_call_rate_for with (config, script, rate, opts) and never
---     spawns a process itself
---   * set_call_rate_for absent (old nvim-m1): the <C-a> handler WARN-notifies,
---     no error thrown

-- ─── rate_value() ──────────────────────────────────────────────────────────
-- rate_value is private-by-convention to the picker module, exposed for tests
-- as call_rates._rate_value. We call the REAL function so any drift in the
-- source breaks this test.
local call_rates = require("telescope-m1.pickers.call_rates")
local rate_value = call_rates._rate_value

describe("call_rates picker: rate_value logic", function()
  it('"startup" (any case) → "startup"', function()
    assert.equals("startup", rate_value("startup"))
    assert.equals("startup", rate_value("Startup"))
    assert.equals("startup", rate_value("STARTUP"))
    assert.equals("startup", rate_value("On Startup"))
  end)

  it('"100Hz" → "100"', function()
    assert.equals("100", rate_value("100Hz"))
  end)

  it('"1000Hz" → "1000"', function()
    assert.equals("1000", rate_value("1000Hz"))
  end)

  it('"10Hz" → "10"', function()
    assert.equals("10", rate_value("10Hz"))
  end)

  it("a label with no Hz suffix is returned unchanged", function()
    -- Defensive: if the rates list ever carries a bare number the gsub is a
    -- no-op and the value flows through unaltered.
    assert.equals("500", rate_value("500"))
  end)

  it("does not strip Hz from the middle of a label", function()
    -- "OnHz100" should not be mutated because Hz is not the suffix.
    assert.equals("OnHz100", rate_value("OnHz100"))
  end)
end)

-- ─── entry array access ────────────────────────────────────────────────────

describe("call_rates picker: entry[1] array access", function()
  -- The picker uses finders.new_table({ results = rates }) with no custom
  -- entry_maker, so Telescope wraps each string as entry[1].  The picker
  -- code accesses entry[1] (not entry.value) to get the rate label.

  it("entry[1] holds the rate label string", function()
    -- Simulate the table Telescope creates when entry_maker is absent.
    local rates = { "100Hz", "1000Hz", "On Startup" }
    for _, label in ipairs(rates) do
      -- Telescope stores the raw value at [1] when no entry_maker is given.
      local entry = { label }
      assert.equals(label, entry[1])
    end
  end)

  it("rate_value applied to entry[1] gives the expected hz string", function()
    local cases = {
      { entry = { "100Hz" }, want = "100" },
      { entry = { "1000Hz" }, want = "1000" },
      { entry = { "On Startup" }, want = "startup" },
    }
    for _, tc in ipairs(cases) do
      assert.equals(tc.want, rate_value(tc.entry[1]))
    end
  end)
end)

-- ─── nvim-m1 absent path ───────────────────────────────────────────────────

describe("call_rates picker: nvim-m1 not installed", function()
  -- The picker calls `pcall(require, "nvim-m1")` using the `require`
  -- upvalue captured at module-load time.  We simulate "not installed" by:
  --   1. Removing the cache entry so require() re-runs the loaders.
  --   2. Installing a package.preload entry that throws, so the loader fails.
  -- This guarantees pcall(require, "nvim-m1") → ok=false regardless of
  -- whether nvim-m1 is actually present in the runtimepath.

  local orig_nvim_m1
  local orig_preload

  before_each(function()
    orig_nvim_m1 = package.loaded["nvim-m1"]
    orig_preload = package.preload["nvim-m1"]
  end)

  after_each(function()
    package.loaded["nvim-m1"] = orig_nvim_m1
    package.preload["nvim-m1"] = orig_preload
  end)

  it("notifies with WARN and returns without error when nvim-m1 is absent", function()
    local notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end

    -- Force require("nvim-m1") to fail by installing an error-throwing
    -- preloader and clearing the cache.
    package.loaded["nvim-m1"] = nil
    package.preload["nvim-m1"] = function()
      error("module 'nvim-m1' not found (test stub)")
    end

    assert.has_no.errors(function()
      require("telescope-m1.pickers.call_rates")({})
    end)

    vim.notify = orig_notify

    assert.equals(1, #notified)
    assert.equals(vim.log.levels.WARN, notified[1].level)
    assert.is_truthy(notified[1].msg:find("nvim-m1", 1, true))
  end)
end)

-- ─── set_call_rate_for delegation (behavioural) ────────────────────────────

describe("call_rates picker: set_call_rate_for delegation", function()
  -- Drive the REAL <C-a> handler the picker registers, with a fake nvim-m1 /
  -- nvim-m1.project injected via package.loaded, and assert it delegates to
  -- project.set_call_rate_for with (config, script, rate, opts) — never
  -- spawning a process itself.

  local orig_nvim_m1
  local orig_nvim_m1_project
  local orig_pickers_new
  local orig_get_selected
  local orig_close
  local orig_ui_input
  local orig_replace
  local orig_system
  local orig_systemlist
  local orig_jobstart
  local orig_notify

  local pickers = require("telescope.pickers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  before_each(function()
    orig_nvim_m1 = package.loaded["nvim-m1"]
    orig_nvim_m1_project = package.loaded["nvim-m1.project"]
    orig_pickers_new = pickers.new
    orig_get_selected = action_state.get_selected_entry
    orig_close = actions.close
    orig_ui_input = vim.ui.input
    orig_replace = actions.select_default.replace
    orig_system = vim.fn.system
    orig_systemlist = vim.fn.systemlist
    orig_jobstart = vim.fn.jobstart
    orig_notify = vim.notify
  end)

  after_each(function()
    package.loaded["nvim-m1"] = orig_nvim_m1
    package.loaded["nvim-m1.project"] = orig_nvim_m1_project
    pickers.new = orig_pickers_new
    action_state.get_selected_entry = orig_get_selected
    actions.close = orig_close
    vim.ui.input = orig_ui_input
    actions.select_default.replace = orig_replace
    vim.fn.system = orig_system
    vim.fn.systemlist = orig_systemlist
    vim.fn.jobstart = orig_jobstart
    vim.notify = orig_notify
  end)

  --- Run the picker with pickers.new stubbed to capture the picker definition,
  --- then invoke its attach_mappings to capture the <C-a> handler. Returns the
  --- captured handler (or nil if none was registered).
  ---@param entry table        the "selected" rate entry (entry[1] = label)
  ---@return function|nil c_a_handler
  local function capture_c_a_handler(entry)
    local captured_def
    pickers.new = function(_, def)
      captured_def = def
      return { find = function() end }
    end
    -- Spawn guards: any process spawn turns into a hard failure.
    vim.fn.system = function()
      error("picker must not call vim.fn.system")
    end
    vim.fn.systemlist = function()
      error("picker must not call vim.fn.systemlist")
    end
    vim.fn.jobstart = function()
      error("picker must not call vim.fn.jobstart")
    end
    actions.close = function() end
    action_state.get_selected_entry = function()
      return entry
    end
    -- select_default:replace just records the <CR> handler; ignore it here.
    actions.select_default.replace = function() end

    require("telescope-m1.pickers.call_rates")({})

    assert.is_not_nil(captured_def, "pickers.new must be called")
    assert.is_function(captured_def.attach_mappings, "attach_mappings must be set")

    local handlers = {}
    local function fake_map(_, lhs, fn)
      handlers[lhs] = fn
    end
    captured_def.attach_mappings(0, fake_map)
    return handlers["<C-a>"]
  end

  it("the <C-a> handler delegates to set_call_rate_for, never spawning", function()
    local calls = {}
    local fake_config = { bin = "/usr/local/bin/m1" }
    package.loaded["nvim-m1"] = { config = fake_config }
    package.loaded["nvim-m1.project"] = {
      rates = function()
        return { "100Hz", "1000Hz" }
      end,
      set_call_rate_for = function(cfg, script, rate, opts)
        calls[#calls + 1] = { cfg = cfg, script = script, rate = rate, opts = opts }
      end,
    }
    vim.notify = function() end
    -- vim.ui.input feeds the script name to its callback synchronously.
    vim.ui.input = function(_, on_confirm)
      on_confirm("Root.Engine.Control")
    end

    local handler = capture_c_a_handler({ "100Hz" })
    assert.is_function(handler, "<C-a> must be mapped to a handler")

    handler() -- drive the real delegation path

    assert.equals(1, #calls)
    assert.equals(fake_config, calls[1].cfg)
    assert.equals("Root.Engine.Control", calls[1].script)
    assert.equals("100", calls[1].rate)
    assert.is_table(calls[1].opts)
    assert.is_truthy(calls[1].opts.label:find("call rate", 1, true))
  end)

  it("the <C-a> handler does nothing when the input is cancelled", function()
    local calls = {}
    package.loaded["nvim-m1"] = { config = {} }
    package.loaded["nvim-m1.project"] = {
      rates = function()
        return { "100Hz" }
      end,
      set_call_rate_for = function()
        calls[#calls + 1] = true
      end,
    }
    vim.notify = function() end
    vim.ui.input = function(_, on_confirm)
      on_confirm(nil) -- user pressed <Esc>
    end

    local handler = capture_c_a_handler({ "100Hz" })
    handler()
    assert.equals(0, #calls, "no delegation when the script prompt is cancelled")
  end)

  it("the <C-a> handler WARN-guards when set_call_rate_for is missing", function()
    -- Old nvim-m1 (< v0.11.0): project has no set_call_rate_for. The handler
    -- must notify WARN and not error.
    package.loaded["nvim-m1"] = { config = {} }
    package.loaded["nvim-m1.project"] = {
      rates = function()
        return { "100Hz" }
      end,
      -- set_call_rate_for deliberately absent.
    }
    local notified = {}
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end
    vim.ui.input = function(_, on_confirm)
      on_confirm("Root.Engine.Control")
    end

    local handler = capture_c_a_handler({ "100Hz" })

    assert.has_no.errors(function()
      handler()
    end)

    assert.equals(1, #notified, "exactly one WARN when set_call_rate_for is missing")
    assert.equals(vim.log.levels.WARN, notified[1].level)
    assert.is_truthy(
      notified[1].msg:find("v0.11.0", 1, true),
      "the WARN should point at the nvim-m1 version requirement"
    )
  end)
end)

-- ─── empty-rates path ─────────────────────────────────────────────────────

describe("call_rates picker: empty rates list", function()
  -- The picker calls `pcall(require, "nvim-m1")` using the `require`
  -- upvalue captured at module-load time, not `_G.require`.  Injecting
  -- fakes via `package.loaded` is the only reliable way to intercept it.

  local orig_nvim_m1
  local orig_nvim_m1_project

  before_each(function()
    orig_nvim_m1 = package.loaded["nvim-m1"]
    orig_nvim_m1_project = package.loaded["nvim-m1.project"]
  end)

  after_each(function()
    package.loaded["nvim-m1"] = orig_nvim_m1
    package.loaded["nvim-m1.project"] = orig_nvim_m1_project
  end)

  it("notifies with INFO and returns without error when rates is empty", function()
    local notified = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg = msg, level = level }
    end

    -- Inject fakes into the module cache so the picker's `require` calls
    -- pick them up without touching `_G.require`.
    local fake_project = {
      rates = function()
        return {}
      end,
    }
    package.loaded["nvim-m1"] = { config = {} }
    package.loaded["nvim-m1.project"] = fake_project

    assert.has_no.errors(function()
      require("telescope-m1.pickers.call_rates")({})
    end)

    vim.notify = orig_notify

    assert.equals(1, #notified)
    assert.equals(vim.log.levels.INFO, notified[1].level)
    assert.is_truthy(notified[1].msg:find("no execution-rate clocks", 1, true))
  end)
end)
