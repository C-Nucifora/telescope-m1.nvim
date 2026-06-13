describe("telescope m1 extension", function()
  local telescope = require("telescope")

  it("loads and exposes the four pickers", function()
    telescope.setup({})
    assert.has_no.errors(function()
      telescope.load_extension("m1")
    end)

    local ext = telescope.extensions.m1
    assert.is_function(ext.workspace_symbols)
    assert.is_function(ext.components)
    assert.is_function(ext.lint_rules)
    assert.is_function(ext.call_rates)
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
    assert.is_function(telescope.extensions.m1.call_rates)
  end)
end)
