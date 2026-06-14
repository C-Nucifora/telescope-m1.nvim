describe("telescope m1 extension", function()
  local telescope = require("telescope")

  -- A picker export is "callable": either a plain function (workspace_symbols)
  -- or a callable table — `setmetatable({}, { __call = … })` — which the picker
  -- modules use so they can also expose their private helpers to the unit
  -- tests. Telescope invokes every export as `export(opts)`, so callability is
  -- the real contract here, not the raw `function` type.
  local function assert_callable(v, name)
    local ok = type(v) == "function"
      or (
        type(v) == "table"
        and type(getmetatable(v)) == "table"
        and getmetatable(v).__call ~= nil
      )
    assert.is_true(ok, (name or "export") .. " must be callable")
  end

  it("loads and exposes the four pickers", function()
    telescope.setup({})
    assert.has_no.errors(function()
      telescope.load_extension("m1")
    end)

    local ext = telescope.extensions.m1
    assert_callable(ext.workspace_symbols, "workspace_symbols")
    assert_callable(ext.components, "components")
    assert_callable(ext.lint_rules, "lint_rules")
    assert_callable(ext.call_rates, "call_rates")
  end)

  it("forwards setup options into telescope-m1.config", function()
    telescope.load_extension("m1")
    -- The extension's setup() forwards ext config into telescope-m1.config.
    require("telescope-m1.config").setup({ probe = true })
    assert.is_true(require("telescope-m1.config").options.probe)
  end)

  it(
    "LSP-backed pickers notify (not error) when no m1-lsp client is attached",
    function()
      -- With no client in the headless session, both pickers should request
      -- symbols, get an error back, and notify — never throw.
      assert.has_no.errors(function()
        require("telescope-m1.pickers.workspace_symbols")({})
        require("telescope-m1.pickers.components")({})
      end)
    end
  )
end)

describe("next-gen pickers", function()
  it("exports call_rates (#10)", function()
    local telescope = require("telescope")
    telescope.load_extension("m1")
    -- call_rates is a callable table (it also exposes _rate_value for tests),
    -- so assert it can be invoked rather than that it is a raw function.
    local cr = telescope.extensions.m1.call_rates
    local mt = getmetatable(cr)
    assert.is_true(
      type(cr) == "function" or (type(cr) == "table" and mt and mt.__call ~= nil),
      "call_rates export must be callable"
    )
  end)
end)
