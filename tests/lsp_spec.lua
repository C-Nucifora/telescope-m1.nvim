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

describe("telescope-m1.lsp.find_client", function()
  local orig_get_clients

  before_each(function()
    orig_get_clients = vim.lsp.get_clients
  end)

  after_each(function()
    vim.lsp.get_clients = orig_get_clients
  end)

  it("ignores a generic LSP that merely advertises workspaceSymbolProvider", function()
    -- lua_ls et al. advertise workspaceSymbolProvider but are not m1-lsp.
    -- Picking one would send workspace/symbol to the wrong server and present
    -- non-M1 results; we must treat "no m1-lsp client" as no client.
    vim.lsp.get_clients = function()
      return {
        {
          name = "lua_ls",
          config = { filetypes = { "lua" } },
          server_capabilities = { workspaceSymbolProvider = true },
        },
      }
    end
    assert.is_nil(m1_lsp.find_client())
  end)

  it("matches an m1-lsp client by its m1scr filetype even under an odd name", function()
    vim.lsp.get_clients = function()
      return {
        {
          name = "lua_ls",
          config = { filetypes = { "lua" } },
          server_capabilities = { workspaceSymbolProvider = true },
        },
        {
          name = "my-custom-m1",
          config = { filetypes = { "m1scr" } },
          server_capabilities = { workspaceSymbolProvider = true },
        },
      }
    end
    local c = m1_lsp.find_client()
    assert.is_not_nil(c)
    assert.equals("my-custom-m1", c.name)
  end)

  it("matches an m1-lsp client by its canonical name", function()
    vim.lsp.get_clients = function()
      return {
        { name = "m1lsp", config = { filetypes = {} }, server_capabilities = {} },
      }
    end
    local c = m1_lsp.find_client()
    assert.is_not_nil(c)
    assert.equals("m1lsp", c.name)
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

describe("telescope-m1.lsp.kind_icon (#27)", function()
  local config = require("telescope-m1.config")
  local kinds = {
    "Variable",
    "Property",
    "Constant",
    "Function",
    "Method",
    "Array",
    "Namespace",
    "Object",
  }

  after_each(function()
    config.options.icons = "ascii"
  end)

  it("every mapped kind has a non-empty ascii icon by default", function()
    config.options.icons = "ascii"
    for _, name in ipairs(kinds) do
      local icon = m1_lsp.kind_icon(vim.lsp.protocol.SymbolKind[name])
      assert.is_true(icon ~= "", name .. " must have an icon")
      assert.is_true(
        #icon == 1,
        name .. " ascii icon must be a single byte, got " .. icon
      )
    end
  end)

  it("nerd set is non-empty for every mapped kind", function()
    config.options.icons = "nerd"
    for _, name in ipairs(kinds) do
      assert.is_true(
        m1_lsp.kind_icon(vim.lsp.protocol.SymbolKind[name]) ~= "",
        name .. " must have a nerd icon"
      )
    end
  end)

  it("icons = false blanks the column; unknown kinds stay empty", function()
    config.options.icons = false
    assert.equals("", m1_lsp.kind_icon(vim.lsp.protocol.SymbolKind.Variable))
    config.options.icons = "ascii"
    assert.equals("", m1_lsp.kind_icon(9999))
  end)
end)
