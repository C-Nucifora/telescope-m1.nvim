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

-- ─── qflist_previewer fallback (behavioural) ─────────────────────────────────

describe("workspace_symbols picker: conf.qflist_previewer fallback", function()
  -- When a picker spec carries no custom previewer, symbol_picker.open must
  -- pass conf.qflist_previewer(opts) to pickers.new; when it carries one, that
  -- custom previewer must flow through unchanged. We stub pickers.new to
  -- capture the definition table it would build, then assert on the real value.

  local symbol_picker = require("telescope-m1.symbol_picker")
  local pickers = require("telescope.pickers")
  local conf = require("telescope.config").values

  local orig_pickers_new
  local orig_qflist
  before_each(function()
    orig_pickers_new = pickers.new
    orig_qflist = conf.qflist_previewer
  end)
  after_each(function()
    pickers.new = orig_pickers_new
    conf.qflist_previewer = orig_qflist
  end)

  --- Capture the picker definition symbol_picker.open hands to pickers.new.
  local function captured_def(opts, spec)
    local def
    pickers.new = function(_, d)
      def = d
      return { find = function() end }
    end
    symbol_picker.open(opts, spec)
    return def
  end

  it("falls back to conf.qflist_previewer(opts) when spec.previewer is nil", function()
    -- conf.qflist_previewer mints a fresh previewer object per call, so we
    -- can't compare by identity against a second call. Instead spy on it:
    -- a sentinel returned from the fallback must reach pickers.new, and it
    -- must be invoked with the same opts the picker was opened with.
    local opts = { layout_strategy = "vertical" }
    local sentinel = { _marker = "qflist-fallback" }
    local got_opts
    conf.qflist_previewer = function(o)
      got_opts = o
      return sentinel
    end

    local def = captured_def(opts, {
      title = "M1 Workspace Symbols",
      entries = { { name = "Root.Speed", kind_label = "Variable" } },
      -- previewer deliberately omitted → fallback path
    })

    assert.is_not_nil(def, "pickers.new must be called")
    assert.equals(sentinel, def.previewer, "the qflist fallback must reach pickers.new")
    assert.equals(
      opts,
      got_opts,
      "qflist_previewer must be called with the picker opts"
    )
  end)

  it("uses spec.previewer unchanged when one is supplied", function()
    -- A supplied previewer must flow through untouched; the fallback must NOT
    -- run, so qflist_previewer is wired to fail if it is consulted.
    conf.qflist_previewer = function()
      error("qflist_previewer must not be called when spec.previewer is set")
    end
    local custom = { _marker = "custom-previewer" }
    local def = captured_def({}, {
      title = "M1 Components",
      entries = { { name = "Root.Engine", kind_label = "Namespace" } },
      previewer = custom,
    })
    assert.is_not_nil(def)
    assert.equals(custom, def.previewer, "a supplied previewer must not be replaced")
  end)
end)

describe("workspace_symbols picker: no custom previewer (fallback applies)", function()
  -- The workspace_symbols picker supplies no previewer of its own, so the
  -- spec that reaches symbol_picker.open carries previewer=nil and the
  -- qflist fallback applies. Drive the real picker and capture the spec.

  local m1_lsp = require("telescope-m1.lsp")
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

  it("from_lsp is called with a spec that has no previewer", function()
    local captured_spec
    package.loaded["telescope-m1.symbol_picker"] = {
      from_lsp = function(_, spec)
        captured_spec = spec
      end,
      open = function() end,
    }

    package.loaded["telescope-m1.pickers.workspace_symbols"] = nil
    require("telescope-m1.pickers.workspace_symbols")({})

    assert.is_not_nil(captured_spec, "from_lsp must be called")
    assert.is_nil(
      captured_spec.previewer,
      "workspace_symbols must not set a custom previewer"
    )
  end)
end)

-- ─── facet composition (type:/security:/tag:/rate:) ─────────────────────────
-- m1-lsp's workspace/symbol parses leading `key:value` facet tokens
-- server-side (workspace_symbol.rs). Telescope's prompt only fuzzy-filters the
-- already-fetched rows, so typing `type:enum` into the prompt matched zero
-- rows. The picker therefore composes facet opts into the LSP query so the
-- slice reaches the server verbatim. These tests drive the REAL composition.

describe("workspace_symbols picker: facet query composition", function()
  -- compose_query is private-by-convention, exposed for tests as
  -- ._compose_query. Calling the REAL function means any drift breaks here.
  local ws = require("telescope-m1.pickers.workspace_symbols")
  local compose = ws._compose_query

  it("forwards a single type facet as `type:<v>`", function()
    assert.equals("type:enum", compose({ type = "enum" }))
  end)

  it("forwards security/tag/rate facets verbatim", function()
    assert.equals("security:Tune", compose({ security = "Tune" }))
    assert.equals("tag:Engine", compose({ tag = "Engine" }))
    assert.equals("rate:100", compose({ rate = 100 }))
  end)

  it("composes multiple facets in a deterministic order", function()
    -- tag, security, rate, type — fixed so the query is stable/testable.
    assert.equals(
      "tag:Engine security:Tune rate:100 type:enum",
      compose({ type = "enum", security = "Tune", tag = "Engine", rate = 100 })
    )
  end)

  it("appends free `query` text after the facets", function()
    assert.equals("type:enum torque", compose({ type = "enum", query = "torque" }))
  end)

  it("a bare query with no facets passes straight through", function()
    assert.equals("Root.Speed", compose({ query = "Root.Speed" }))
  end)

  it("empty opts compose to the empty (all-symbols) query", function()
    assert.equals("", compose({}))
    assert.equals("", compose({ type = "", query = "" }))
  end)
end)

describe("workspace_symbols picker: facet opts reach the LSP query", function()
  -- End-to-end through the real picker: a facet opt must arrive at
  -- m1_lsp.workspace_symbols as the spec.query (the call_rates spec proves
  -- from_lsp forwards query; here we prove the picker composes it).
  local orig_symbol_picker

  before_each(function()
    orig_symbol_picker = package.loaded["telescope-m1.symbol_picker"]
  end)
  after_each(function()
    package.loaded["telescope-m1.symbol_picker"] = orig_symbol_picker
  end)

  it("a type facet opt reaches from_lsp as `type:enum`", function()
    local captured_query
    package.loaded["telescope-m1.symbol_picker"] = {
      from_lsp = function(_, spec)
        captured_query = spec.query
      end,
      open = function() end,
    }

    package.loaded["telescope-m1.pickers.workspace_symbols"] = nil
    require("telescope-m1.pickers.workspace_symbols")({ type = "enum" })

    assert.equals("type:enum", captured_query)
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
