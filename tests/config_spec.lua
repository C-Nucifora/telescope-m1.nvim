-- config.setup validation (#27): the documented `icons` values are
-- "ascii" | "nerd" | false. A typo (e.g. "nerd-fonts") used to be merged in
-- blindly and then silently degrade to ascii in kind_icon with no feedback, so
-- a misconfiguration looked identical to the default. setup() now validates the
-- value: valid ones pass through untouched, an invalid one emits a single WARN
-- notify and resets to "ascii".
local config = require("telescope-m1.config")

describe("telescope-m1.config.setup icons validation", function()
  local orig_notify

  before_each(function()
    orig_notify = vim.notify
    config.options.icons = "ascii"
  end)

  after_each(function()
    vim.notify = orig_notify
    config.options.icons = "ascii"
  end)

  -- Run setup with `ext_config` while capturing every vim.notify call so the
  -- real validation runs without touching a live UI.
  local function run_setup(ext_config)
    local notifications = {}
    vim.notify = function(msg, level)
      notifications[#notifications + 1] = { msg = msg, level = level }
    end
    config.setup(ext_config)
    return notifications
  end

  it("passes the three valid values through unchanged with no notify", function()
    for _, value in ipairs({ "ascii", "nerd" }) do
      local notes = run_setup({ icons = value })
      assert.equals(value, config.options.icons)
      assert.equals(0, #notes, value .. " must not notify")
    end

    -- `false` is special-cased (ipairs skips a boolean entry).
    local notes = run_setup({ icons = false })
    assert.equals(false, config.options.icons)
    assert.equals(0, #notes, "false must not notify")
  end)

  it("does not notify when icons is left at its default", function()
    local notes = run_setup(nil)
    assert.equals("ascii", config.options.icons)
    assert.equals(0, #notes)
  end)

  it("warns once and resets to ascii on an invalid string", function()
    local notes = run_setup({ icons = "nerd-fonts" })
    assert.equals("ascii", config.options.icons)
    assert.equals(1, #notes, "exactly one notify expected")
    assert.equals(vim.log.levels.WARN, notes[1].level)
    assert.is_truthy(
      notes[1].msg:find("nerd-fonts", 1, true),
      "message should name the bad value"
    )
    assert.is_truthy(notes[1].msg:find("ascii", 1, true))
  end)

  it("warns and resets on a case-variant of a valid value", function()
    local notes = run_setup({ icons = "ASCII" })
    assert.equals("ascii", config.options.icons)
    assert.equals(1, #notes)
    assert.equals(vim.log.levels.WARN, notes[1].level)
  end)

  it("warns and resets on a non-string, non-false truthy value", function()
    local notes = run_setup({ icons = {} })
    assert.equals("ascii", config.options.icons)
    assert.equals(1, #notes)
    assert.equals(vim.log.levels.WARN, notes[1].level)
  end)
end)
