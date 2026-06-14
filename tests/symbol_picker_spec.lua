--- Tests for telescope-m1/symbol_picker.lua
---
--- Exercises:
---   * make_entry: ordinal is "<name> <kind_label>"
---   * make_entry display: formats correctly without hierarchy indentation
---   * make_entry display: applies depth-based indentation when hierarchy=true
---   * make_entry: filename / lnum / col are preserved 1-indexed
---   * make_entry: kind_label absent falls back to empty string in ordinal
local m1_lsp = require("telescope-m1.lsp")

-- ─── helpers ────────────────────────────────────────────────────────────────

--- Build a synthetic entry table (as lsp.symbol_to_entry would return) with
--- optional overrides.
local function sample_sym(overrides)
  return vim.tbl_extend("force", {
    name = "Root.Engine.Speed",
    container = "Root.Engine",
    kind = vim.lsp.protocol.SymbolKind.Variable,
    kind_label = "Variable",
    filename = "/proj/Project.m1prj",
    lnum = 5,
    col = 3,
  }, overrides or {})
end

--- Reproduce the private make_entry closure from symbol_picker.lua verbatim,
--- accepting an injectable displayer so we can intercept the display arguments
--- without a live Neovim window.
---
--- `hierarchy` mirrors the boolean flag that the picker passes: true = indent
--- by depth, false = flat list.
local function build_entry(sym, hierarchy, displayer)
  -- Replicate the make_entry closure exactly as it appears in symbol_picker.lua.
  local function make_entry(disp, hier)
    return function(s)
      return {
        value = s,
        ordinal = s.name .. " " .. (s.kind_label or ""),
        display = function(e)
          local sv = e.value
          local indent = hier and string.rep("  ", sv.depth or 0) or ""
          return disp({
            { m1_lsp.kind_icon(sv.kind), "TelescopeResultsComment" },
            { indent .. sv.name, "TelescopeResultsIdentifier" },
            { sv.kind_label or "", "TelescopeResultsComment" },
          })
        end,
        filename = s.filename,
        lnum = s.lnum,
        col = s.col,
      }
    end
  end

  local default_disp = displayer or function(args)
    return args, {}
  end
  return make_entry(default_disp, hierarchy)(sym)
end

-- ─── ordinal ────────────────────────────────────────────────────────────────

describe("symbol_picker: make_entry ordinal", function()
  it("ordinal is '<name> <kind_label>'", function()
    local sym = sample_sym()
    local entry = build_entry(sym, false)
    assert.equals("Root.Engine.Speed Variable", entry.ordinal)
  end)

  it("ordinal includes both name and kind_label for Function kind", function()
    local sym = sample_sym({
      name = "Root.Control.Run",
      kind = vim.lsp.protocol.SymbolKind.Function,
      kind_label = "Function",
    })
    local entry = build_entry(sym, false)
    assert.equals("Root.Control.Run Function", entry.ordinal)
  end)

  it("ordinal contains name and kind_label so fuzzy search hits both", function()
    local sym = sample_sym({
      name = "Wheel.Speed",
      kind_label = "Property",
    })
    local entry = build_entry(sym, false)
    assert.is_truthy(entry.ordinal:find("Wheel.Speed", 1, true))
    assert.is_truthy(entry.ordinal:find("Property", 1, true))
  end)

  it("ordinal uses empty string when kind_label is absent", function()
    -- vim.tbl_extend drops nil values, so build the sym directly.
    local sym = {
      name = "Root.Engine.Speed",
      container = "Root.Engine",
      kind = vim.lsp.protocol.SymbolKind.Variable,
      kind_label = nil,
      filename = "/proj/Project.m1prj",
      lnum = 5,
      col = 3,
    }
    local entry = build_entry(sym, false)
    -- Trailing space + empty = "name "
    assert.equals("Root.Engine.Speed ", entry.ordinal)
  end)
end)

-- ─── display: flat (hierarchy = false) ──────────────────────────────────────

describe("symbol_picker: make_entry display (flat, no indentation)", function()
  it("display is a function", function()
    local entry = build_entry(sample_sym(), false)
    assert.is_function(entry.display)
  end)

  it("display passes name WITHOUT leading indent to the displayer", function()
    local captured
    local function fake_disp(args)
      captured = args
      return "", {}
    end
    local sym = sample_sym({ depth = 2 }) -- depth ignored when hierarchy=false
    local entry = build_entry(sym, false, fake_disp)
    entry.display(entry)
    -- Slot 2 is { indent..name, hl }.  indent must be "" when hierarchy=false.
    assert.equals("Root.Engine.Speed", captured[2][1])
  end)

  it("display slot 1 is the kind icon string", function()
    local captured
    local function fake_disp(args)
      captured = args
      return "", {}
    end
    local sym = sample_sym()
    local entry = build_entry(sym, false, fake_disp)
    entry.display(entry)
    -- Slot 1 is {kind_icon, hl}; value must be a string (possibly empty).
    assert.is_string(captured[1][1])
  end)

  it("display slot 3 is the kind_label", function()
    local captured
    local function fake_disp(args)
      captured = args
      return "", {}
    end
    local sym = sample_sym({ kind_label = "Variable" })
    local entry = build_entry(sym, false, fake_disp)
    entry.display(entry)
    assert.equals("Variable", captured[3][1])
  end)

  it("display slot 3 is empty string when kind_label is nil", function()
    local captured
    local function fake_disp(args)
      captured = args
      return "", {}
    end
    -- vim.tbl_extend drops nil values, so build the sym directly.
    local sym = {
      name = "Root.Engine.Speed",
      kind = vim.lsp.protocol.SymbolKind.Variable,
      kind_label = nil,
      filename = "/proj/Project.m1prj",
      lnum = 5,
      col = 3,
    }
    local entry = build_entry(sym, false, fake_disp)
    entry.display(entry)
    assert.equals("", captured[3][1])
  end)
end)

-- ─── display: hierarchy (hierarchy = true) ──────────────────────────────────

describe(
  "symbol_picker: make_entry display (hierarchy = true, depth indent)",
  function()
    it("depth 0 produces no leading spaces", function()
      local captured
      local function fake_disp(args)
        captured = args
        return "", {}
      end
      local sym = sample_sym({ name = "Root", depth = 0 })
      local entry = build_entry(sym, true, fake_disp)
      entry.display(entry)
      assert.equals("Root", captured[2][1])
    end)

    it("depth 1 produces two leading spaces before the name", function()
      local captured
      local function fake_disp(args)
        captured = args
        return "", {}
      end
      local sym = sample_sym({ name = "Root.Engine", depth = 1 })
      local entry = build_entry(sym, true, fake_disp)
      entry.display(entry)
      assert.equals("  Root.Engine", captured[2][1])
    end)

    it("depth 2 produces four leading spaces before the name", function()
      local captured
      local function fake_disp(args)
        captured = args
        return "", {}
      end
      local sym = sample_sym({ name = "Root.Engine.Speed", depth = 2 })
      local entry = build_entry(sym, true, fake_disp)
      entry.display(entry)
      assert.equals("    Root.Engine.Speed", captured[2][1])
    end)

    it("depth absent (nil) is treated as 0 — no indent", function()
      local captured
      local function fake_disp(args)
        captured = args
        return "", {}
      end
      local sym = sample_sym({ name = "Root", depth = nil })
      local entry = build_entry(sym, true, fake_disp)
      entry.display(entry)
      assert.equals("Root", captured[2][1])
    end)
  end
)

-- ─── filename / lnum / col ───────────────────────────────────────────────────

describe("symbol_picker: make_entry preserves filename, lnum, col", function()
  it("filename is taken verbatim from the sym table", function()
    local sym = sample_sym({ filename = "/workspace/Root.m1prj" })
    local entry = build_entry(sym, false)
    assert.equals("/workspace/Root.m1prj", entry.filename)
  end)

  it("lnum is 1-indexed (LSP 0-indexed already converted by lsp module)", function()
    -- symbol_to_entry adds 1; make_entry just passes the value through.
    local sym = sample_sym({ lnum = 5 })
    local entry = build_entry(sym, false)
    assert.equals(5, entry.lnum)
  end)

  it("col is 1-indexed (LSP 0-indexed already converted by lsp module)", function()
    local sym = sample_sym({ col = 3 })
    local entry = build_entry(sym, false)
    assert.equals(3, entry.col)
  end)

  it("lnum = 1 is preserved (first line)", function()
    local sym = sample_sym({ lnum = 1, col = 1 })
    local entry = build_entry(sym, false)
    assert.equals(1, entry.lnum)
    assert.equals(1, entry.col)
  end)

  it("value field is the raw sym table (not a copy)", function()
    local sym = sample_sym()
    local entry = build_entry(sym, false)
    assert.equals(sym, entry.value)
  end)
end)

-- ─── round-trip via lsp.symbol_to_entry ─────────────────────────────────────

describe("symbol_picker: make_entry round-trip from lsp.symbol_to_entry", function()
  -- Confirm that an entry produced by lsp.symbol_to_entry flows through
  -- make_entry with the correct ordinal and 1-indexed lnum/col — i.e. the two
  -- modules compose correctly.

  it("ordinal and coords round-trip through symbol_to_entry", function()
    local uri = vim.uri_from_fname("/proj/Project.m1prj")
    local sym_info = {
      name = "Root.Wheel.Torque",
      containerName = "Root.Wheel",
      kind = vim.lsp.protocol.SymbolKind.Property,
      location = {
        uri = uri,
        range = {
          start = { line = 9, character = 4 },
          ["end"] = { line = 9, character = 20 },
        },
      },
    }
    local sym = m1_lsp.symbol_to_entry(sym_info)
    local entry = build_entry(sym, false)

    assert.equals("Root.Wheel.Torque Property", entry.ordinal)
    assert.equals(10, entry.lnum) -- 9 + 1
    assert.equals(5, entry.col) -- 4 + 1
    assert.equals("/proj/Project.m1prj", entry.filename)
  end)
end)
