--- Tests for telescope-m1/pickers/workspace_symbols.lua
---
--- Exercises:
---   * entry dispatch: symbol_picker.from_lsp entries become selectable picker
---     rows (verified via the open() call that would receive them)
---   * order preservation: entries arrive at the picker in the same order as
---     the LSP result
---   * qflist_previewer fallback: when no custom previewer is in the spec,
---     conf.qflist_previewer(opts) is used
---   * no-client smoke: picker notifies WARN and returns without error when no
---     m1-lsp client is attached
---
--- Mock pattern: same package.loaded injection used by call_rates_spec.lua.
---   We intercept symbol_picker.open() via package.loaded so we can capture
---   what entries and opts the picker would open with, without spawning a real
---   Telescope window.

local m1_lsp = require("telescope-m1.lsp")

-- ─── helpers ────────────────────────────────────────────────────────────────

--- Build a synthetic LSP SymbolInformation table.
local function make_sym_info(name, kind, line, char, uri)
  uri = uri or vim.uri_from_fname("/proj/Project.m1prj")
  return {
    name = name,
    containerName = nil,
    kind = kind or vim.lsp.protocol.SymbolKind.Variable,
    location = {
      uri = uri,
      range = {
        start = { line = line or 0, character = char or 0 },
        ["end"] = { line = line or 0, character = (char or 0) + 10 },
      },
    },
  }
end

-- ─── entry dispatch from symbol_picker.from_lsp ─────────────────────────────

describe("workspace_symbols picker: entry dispatch via symbol_picker", function()
  -- We intercept symbol_picker.open to capture what entries would be opened,
  -- and we inject a fake m1_lsp.workspace_symbols that calls the callback
  -- synchronously with a controlled result list.

  local orig_symbol_picker
  local orig_ws_symbols

  before_each(function()
    orig_symbol_picker = package.loaded["telescope-m1.symbol_picker"]
    orig_ws_symbols = m1_lsp.workspace_symbols
  end)

  after_each(function()
    package.loaded["telescope-m1.symbol_picker"] = orig_symbol_picker
    m1_lsp.workspace_symbols = orig_ws_symbols
  end)

  it("dispatches LSP results as entries to symbol_picker.open", function()
    local opened_spec

    -- Declare before the table so the from_lsp closure can reference it.
    local fake_sp
    fake_sp = {
      open = function(_, spec)
        opened_spec = spec
      end,
      from_lsp = function(opts, spec)
        -- Replicate the real from_lsp dispatch path so we exercise it.
        m1_lsp.workspace_symbols(spec.query or "", function(entries, err)
          if err or vim.tbl_isempty(entries or {}) then
            return
          end
          if spec.transform then
            entries = spec.transform(entries)
          end
          fake_sp.open(opts, {
            title = spec.title,
            entries = entries,
            hierarchy = spec.hierarchy,
            previewer = spec.previewer,
            attach_mappings = spec.attach_mappings,
          })
        end)
      end,
    }
    package.loaded["telescope-m1.symbol_picker"] = fake_sp

    -- Fake workspace_symbols: calls cb synchronously with two entries.
    local sym_a =
      make_sym_info("Root.Speed", vim.lsp.protocol.SymbolKind.Variable, 2, 0)
    local sym_b =
      make_sym_info("Root.Torque", vim.lsp.protocol.SymbolKind.Property, 5, 4)
    m1_lsp.workspace_symbols = function(_, cb)
      cb({
        m1_lsp.symbol_to_entry(sym_a),
        m1_lsp.symbol_to_entry(sym_b),
      })
    end

    -- Load and call the picker (module may already be cached; clear first).
    package.loaded["telescope-m1.pickers.workspace_symbols"] = nil
    require("telescope-m1.pickers.workspace_symbols")({})

    assert.is_not_nil(opened_spec, "symbol_picker.open must be called")
    assert.equals(2, #opened_spec.entries)
  end)

  it("entries are tables with name and kind_label fields", function()
    local opened_spec

    local fake_sp
    fake_sp = {
      open = function(_, spec)
        opened_spec = spec
      end,
      from_lsp = function(opts, spec)
        m1_lsp.workspace_symbols(spec.query or "", function(entries, err)
          if err or vim.tbl_isempty(entries or {}) then
            return
          end
          fake_sp.open(opts, {
            title = spec.title,
            entries = entries,
          })
        end)
      end,
    }
    package.loaded["telescope-m1.symbol_picker"] = fake_sp

    m1_lsp.workspace_symbols = function(_, cb)
      cb({
        m1_lsp.symbol_to_entry(
          make_sym_info("Root.Engine", vim.lsp.protocol.SymbolKind.Namespace, 0, 0)
        ),
      })
    end

    package.loaded["telescope-m1.pickers.workspace_symbols"] = nil
    require("telescope-m1.pickers.workspace_symbols")({})

    assert.is_not_nil(opened_spec)
    local e = opened_spec.entries[1]
    assert.equals("Root.Engine", e.name)
    assert.equals("Namespace", e.kind_label)
  end)
end)

-- ─── order preservation ──────────────────────────────────────────────────────

describe("workspace_symbols picker: entry order matches LSP result order", function()
  local orig_symbol_picker
  local orig_ws_symbols

  before_each(function()
    orig_symbol_picker = package.loaded["telescope-m1.symbol_picker"]
    orig_ws_symbols = m1_lsp.workspace_symbols
  end)

  after_each(function()
    package.loaded["telescope-m1.symbol_picker"] = orig_symbol_picker
    m1_lsp.workspace_symbols = orig_ws_symbols
  end)

  it("entries arrive at the picker in the same order as the LSP response", function()
    local opened_entries

    local fake_sp
    fake_sp = {
      open = function(_, spec)
        opened_entries = spec.entries
      end,
      from_lsp = function(opts, spec)
        m1_lsp.workspace_symbols(spec.query or "", function(entries, err)
          if err or vim.tbl_isempty(entries or {}) then
            return
          end
          fake_sp.open(opts, { title = spec.title, entries = entries })
        end)
      end,
    }
    package.loaded["telescope-m1.symbol_picker"] = fake_sp

    -- Deliberately non-alphabetical order to prove order is preserved.
    local names = { "Zeta.Channel", "Alpha.Param", "Mu.Func" }
    m1_lsp.workspace_symbols = function(_, cb)
      local entries = {}
      for i, n in ipairs(names) do
        entries[i] = m1_lsp.symbol_to_entry(make_sym_info(n, nil, i - 1, 0))
      end
      cb(entries)
    end

    package.loaded["telescope-m1.pickers.workspace_symbols"] = nil
    require("telescope-m1.pickers.workspace_symbols")({})

    assert.is_not_nil(opened_entries)
    assert.equals(3, #opened_entries)
    assert.equals("Zeta.Channel", opened_entries[1].name)
    assert.equals("Alpha.Param", opened_entries[2].name)
    assert.equals("Mu.Func", opened_entries[3].name)
  end)
end)

-- ─── qflist_previewer fallback ───────────────────────────────────────────────

describe("workspace_symbols picker: conf.qflist_previewer fallback", function()
  -- When the picker spec carries no custom previewer, symbol_picker.open
  -- receives previewer=nil and falls back to conf.qflist_previewer(opts).
  -- We verify this at the source level (same textual-contract pattern as
  -- call_rates_spec) rather than launching a real window.

  it("symbol_picker source uses spec.previewer OR conf.qflist_previewer", function()
    local here = debug.getinfo(1, "S").source:sub(2)
    local src_path = here:gsub(
      "tests/workspace_symbols_spec%.lua$",
      "lua/telescope-m1/symbol_picker.lua"
    )
    local f = assert(io.open(src_path, "r"))
    local src = f:read("*a")
    f:close()

    assert.is_true(
      src:find("qflist_previewer", 1, true) ~= nil,
      "symbol_picker must reference conf.qflist_previewer as fallback"
    )
    assert.is_true(
      src:find("spec.previewer or conf.qflist_previewer", 1, true) ~= nil,
      "fallback must be 'spec.previewer or conf.qflist_previewer'"
    )
  end)

  it("workspace_symbols picker passes no previewer so the fallback applies", function()
    -- The picker source must NOT set a custom previewer; the fallback in
    -- symbol_picker.open is the only thing that supplies one.
    local here = debug.getinfo(1, "S").source:sub(2)
    local src_path = here:gsub(
      "tests/workspace_symbols_spec%.lua$",
      "lua/telescope-m1/pickers/workspace_symbols.lua"
    )
    local f = assert(io.open(src_path, "r"))
    local src = f:read("*a")
    f:close()

    assert.is_nil(
      src:find("previewer", 1, true),
      "workspace_symbols.lua must not set a custom previewer "
        .. "(the qflist fallback in symbol_picker handles it)"
    )
  end)
end)

-- ─── no-client smoke test ────────────────────────────────────────────────────

describe("workspace_symbols picker: no m1-lsp client attached", function()
  local orig_notify
  local orig_schedule

  before_each(function()
    orig_notify = vim.notify
    orig_schedule = vim.schedule
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.schedule = orig_schedule
  end)

  it(
    "notifies with WARN and returns without error when no client is attached",
    function()
      local notified = {}
      vim.notify = function(msg, level)
        notified[#notified + 1] = { msg = msg, level = level }
      end
      -- Run vim.schedule callbacks inline so the notify from from_lsp fires
      -- during the call rather than in a later event-loop tick.
      vim.schedule = function(fn)
        fn()
      end

      -- The headless env has no m1-lsp client, so lsp.workspace_symbols calls
      -- cb(nil, err) synchronously, and our inline vim.schedule fires notify.
      assert.has_no.errors(function()
        package.loaded["telescope-m1.pickers.workspace_symbols"] = nil
        require("telescope-m1.pickers.workspace_symbols")({})
      end)

      -- The WARN must mention "no m1-lsp client" (from lsp.workspace_symbols).
      assert.equals(1, #notified, "exactly one notification expected")
      assert.equals(vim.log.levels.WARN, notified[1].level)
      assert.is_truthy(
        notified[1].msg:find("no m1-lsp client", 1, true),
        "notification must mention 'no m1-lsp client'"
      )
    end
  )
end)
