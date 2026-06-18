--- Rule-explanation previewer (#44) specs.
---
--- The lint_rules picker gains an in-editor previewer that runs the resolved
--- `m1-lint --explain <code>` and renders its rationale into the preview
--- buffer, so headless/SSH users (who can't open the browser docs `<CR>`
--- targets) can still read why a rule exists. Mirrors how component_preview
--- factors a pure render helper + async fetch for unit-testability.
local explain = require("telescope-m1.explain_preview")

describe("telescope-m1.explain_preview.render_lines (#44)", function()
  it("renders the m1-lint --explain text verbatim, split into lines", function()
    local rule = { code = "L004", name = "eq-operator-preferred" }
    local text =
      "L004 eq-operator-preferred\n\nM1 prefers the word operators.\n--fix rewrites."
    local lines = explain.render_lines(rule, text)
    assert.same({
      "L004 eq-operator-preferred",
      "",
      "M1 prefers the word operators.",
      "--fix rewrites.",
    }, lines)
  end)

  it("trims a single trailing newline so there is no blank tail line", function()
    local rule = { code = "L006", name = "float-eq-comparison" }
    local lines = explain.render_lines(rule, "L006 float-eq-comparison\nbody\n")
    assert.same({ "L006 float-eq-comparison", "body" }, lines)
  end)

  it("falls back to the rule name + summary when explain text is nil", function()
    local rule = {
      code = "L006",
      name = "float-eq-comparison",
      summary = "float compared with an equality operator",
    }
    local lines = explain.render_lines(rule, nil)
    local text = table.concat(lines, "\n")
    assert.is_truthy(text:find("L006", 1, true), "code present in fallback")
    assert.is_truthy(text:find("float-eq-comparison", 1, true), "name present")
    assert.is_truthy(
      text:find("float compared with an equality operator", 1, true),
      "summary present in fallback"
    )
  end)

  it("falls back gracefully when explain text is empty", function()
    local rule = { code = "L001", name = "line-too-long", summary = "too long" }
    local lines = explain.render_lines(rule, "")
    assert.is_true(#lines >= 1)
    local text = table.concat(lines, "\n")
    assert.is_truthy(text:find("L001", 1, true))
  end)

  it("tolerates a rule with no summary in the fallback", function()
    local rule = { code = "L099", name = "future-rule" }
    local lines = explain.render_lines(rule, nil)
    local text = table.concat(lines, "\n")
    assert.is_truthy(text:find("L099", 1, true))
    assert.is_truthy(text:find("future-rule", 1, true))
    -- No crash, no stray "nil".
    assert.is_nil(text:find("nil", 1, true))
  end)
end)

describe("telescope-m1.explain_preview.still_current (guard)", function()
  it("is true only when the live selection's code matches the fetched one", function()
    assert.is_true(explain.still_current("L004", "L004"))
  end)

  it("is false when the user has moved to a different rule (stale result)", function()
    -- A slow `--explain L004` that returns after the user moved to L006 must
    -- not paint L004's rationale into the now-L006 buffer.
    assert.is_false(explain.still_current("L006", "L004"))
  end)

  it("is false when the live selection key is nil (telescope mid-swap)", function()
    assert.is_false(explain.still_current(nil, "L004"))
  end)

  it("is false when the live selection key is the empty string", function()
    assert.is_false(explain.still_current("", "L004"))
  end)
end)

describe("telescope-m1.explain_preview.fetch_explain (#44)", function()
  local rules = require("telescope-m1.rules")
  local orig_resolve = rules.resolve_m1_lint
  local orig_system = vim.system
  local orig_schedule = vim.schedule

  before_each(function()
    -- Run scheduled callbacks inline so the async path is deterministic.
    vim.schedule = function(fn)
      fn()
    end
  end)

  after_each(function()
    rules.resolve_m1_lint = orig_resolve
    vim.system = orig_system
    vim.schedule = orig_schedule
  end)

  it("spawns the resolved m1-lint with --explain <code>", function()
    local spawned
    rules.resolve_m1_lint = function()
      return "/bundled/m1-lint"
    end
    vim.system = function(cmd, _opts, on_exit)
      spawned = cmd
      on_exit({ code = 0, stdout = "L004 eq-operator-preferred\nbody" })
      return { kill = function() end }
    end

    local got
    explain.fetch_explain("L004", function(text)
      got = text
    end)

    assert.same({ "/bundled/m1-lint", "--explain", "L004" }, spawned)
    assert.equals("L004 eq-operator-preferred\nbody", got)
  end)

  it("calls back with nil when no m1-lint binary resolves (no spawn)", function()
    local spawned = false
    rules.resolve_m1_lint = function()
      return nil
    end
    vim.system = function()
      spawned = true
      return { kill = function() end }
    end

    local called, got = false, "sentinel"
    explain.fetch_explain("L004", function(text)
      called, got = true, text
    end)

    assert.is_false(spawned, "must not spawn a process without a binary")
    assert.is_true(called, "callback still fires so the previewer can fall back")
    assert.is_nil(got)
  end)

  it("calls back with nil on a non-zero exit (unknown code)", function()
    rules.resolve_m1_lint = function()
      return "m1-lint"
    end
    vim.system = function(_cmd, _opts, on_exit)
      on_exit({ code = 2, stdout = "", stderr = "unknown lint code" })
      return { kill = function() end }
    end

    local got = "sentinel"
    explain.fetch_explain("L999", function(text)
      got = text
    end)
    assert.is_nil(got)
  end)

  it("calls back with nil on empty stdout", function()
    rules.resolve_m1_lint = function()
      return "m1-lint"
    end
    vim.system = function(_cmd, _opts, on_exit)
      on_exit({ code = 0, stdout = "" })
      return { kill = function() end }
    end

    local got = "sentinel"
    explain.fetch_explain("L004", function(text)
      got = text
    end)
    assert.is_nil(got)
  end)
end)
