--- Detail-card previewer (#23) and call-rate delegation (#26) specs.
local preview = require("telescope-m1.component_preview")

describe("telescope-m1.component_preview.render_card (#23)", function()
  it("renders the basic card without details", function()
    local lines =
      preview.render_card({ name = "Root.Engine.Speed", kind_label = "Variable" }, nil)
    assert.equals("Root.Engine.Speed", lines[1])
    assert.is_true(lines[2]:find("─") ~= nil, "rule line under the title")
    assert.is_true(table.concat(lines, "\n"):find("Variable") ~= nil)
  end)

  it("renders every populated detail field and skips empty ones", function()
    local lines = preview.render_card({ name = "Root.X", kind_label = "Property" }, {
      classname = "BuiltIn.Parameter",
      type = "f32",
      unit = "kPa",
      security = "Tune",
      call_rate = "100Hz",
      qty = "Pressure",
      tags = { "Vehicle", "Driver" },
      comment = "line one\nline two",
    })
    local text = table.concat(lines, "\n")
    assert.is_true(text:find("BuiltIn.Parameter", 1, true) ~= nil)
    assert.is_true(text:find("f32", 1, true) ~= nil)
    assert.is_true(text:find("kPa", 1, true) ~= nil)
    assert.is_true(text:find("Tune", 1, true) ~= nil)
    assert.is_true(text:find("100Hz", 1, true) ~= nil)
    assert.is_true(text:find("Vehicle, Driver", 1, true) ~= nil)
    assert.is_true(text:find("line one", 1, true) ~= nil)
    assert.is_true(text:find("line two", 1, true) ~= nil)
  end)

  it("treats json nulls (vim.NIL) and empties as absent", function()
    local lines = preview.render_card({ name = "Root.Y", kind_label = "Variable" }, {
      classname = "BuiltIn.Channel",
      type = vim.NIL,
      unit = "",
      comment = vim.NIL,
    })
    local text = table.concat(lines, "\n")
    assert.is_true(text:find("BuiltIn.Channel", 1, true) ~= nil)
    assert.is_nil(text:find("vim.NIL", 1, true))
    assert.is_nil(text:find("type", 1, true))
  end)
end)

describe("telescope-m1.component_preview.lookup", function()
  it("tolerates the Root. prefix difference in either direction", function()
    local map = { ["Root.A.B"] = { path = "Root.A.B" }, ["C.D"] = { path = "C.D" } }
    assert.is_truthy(preview.lookup(map, "Root.A.B"))
    assert.is_truthy(preview.lookup(map, "A.B"))
    assert.is_truthy(preview.lookup(map, "Root.C.D"))
    assert.is_nil(preview.lookup(map, "Nope"))
  end)
end)

-- The call_rates set-call-rate delegation contract (#26) is exercised
-- behaviourally in call_rates_spec.lua (it drives the real <C-a> handler and
-- asserts project.set_call_rate_for is called with no process spawn), so there
-- is no source-text duplicate of it here.
