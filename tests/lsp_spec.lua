local m1_lsp = require("telescope-m1.lsp")

describe("telescope-m1.lsp.symbol_to_entry", function()
  it("flattens an LSP SymbolInformation into a picker entry", function()
    local uri = vim.uri_from_fname("/tmp/proj/Project.m1prj")
    local sym = {
      name = "Root.Engine.Speed",
      containerName = "Root.Engine",
      kind = vim.lsp.protocol.SymbolKind.Variable, -- channels map to Variable
      location = {
        uri = uri,
        range = {
          start = { line = 4, character = 2 },
          ["end"] = { line = 4, character = 20 },
        },
      },
    }
    local e = m1_lsp.symbol_to_entry(sym)
    assert.equals("Root.Engine.Speed", e.name)
    assert.equals("Root.Engine", e.container)
    assert.equals("Variable", e.kind_label)
    assert.equals("/tmp/proj/Project.m1prj", e.filename)
    -- LSP is 0-indexed; telescope wants 1-indexed line/col.
    assert.equals(5, e.lnum)
    assert.equals(3, e.col)
  end)
end)

describe("telescope-m1.lsp.kind_label", function()
  it("names known SymbolKinds", function()
    assert.equals("Variable", m1_lsp.kind_label(vim.lsp.protocol.SymbolKind.Variable))
    assert.equals("Namespace", m1_lsp.kind_label(vim.lsp.protocol.SymbolKind.Namespace))
    assert.equals("Function", m1_lsp.kind_label(vim.lsp.protocol.SymbolKind.Function))
  end)
end)

describe("telescope-m1.lsp.build_hierarchy", function()
  it("orders by dotted path and tags each entry with its depth", function()
    local entries = {
      { name = "Root.Engine.Speed" },
      { name = "Root" },
      { name = "Root.Engine" },
    }
    local ordered = m1_lsp.build_hierarchy(entries)
    assert.same({ "Root", "Root.Engine", "Root.Engine.Speed" }, {
      ordered[1].name,
      ordered[2].name,
      ordered[3].name,
    })
    assert.equals(0, ordered[1].depth) -- Root
    assert.equals(1, ordered[2].depth) -- Root.Engine
    assert.equals(2, ordered[3].depth) -- Root.Engine.Speed
  end)

  it("does not mutate the input", function()
    local entries = { { name = "B" }, { name = "A" } }
    m1_lsp.build_hierarchy(entries)
    assert.equals("B", entries[1].name)
    assert.is_nil(entries[1].depth)
  end)
end)

describe("telescope-m1.lsp.workspace_symbols", function()
  it("reports an error when no m1-lsp client is attached", function()
    -- No m1 client in the headless test session.
    assert.is_nil(m1_lsp.find_client())
    local got_err
    m1_lsp.workspace_symbols("", function(_, err)
      got_err = err
    end)
    assert.is_not_nil(got_err)
    assert.is_truthy(got_err:find("no m1-lsp client", 1, true))
  end)
end)
