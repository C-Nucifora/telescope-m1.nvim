local ignore = require("telescope-m1.ignore")

describe("telescope-m1.ignore.merge_ignore", function()
  it("creates a [lint] block + ignore in an empty file", function()
    local lines, status = ignore.merge_ignore({}, "L004")
    assert.equals("created", status)
    assert.same({ "[lint]", 'ignore = ["L004"]' }, lines)
  end)

  it("merges into an existing single-line ignore array", function()
    local lines, status =
      ignore.merge_ignore({ "[lint]", 'ignore = ["L001", "L002"]' }, "L004")
    assert.equals("merged", status)
    assert.same({ "[lint]", 'ignore = ["L001", "L002", "L004"]' }, lines)
  end)

  it("merges into a compact (no-space) array", function()
    local lines, status = ignore.merge_ignore({ 'ignore=["L001"]' }, "L002")
    assert.equals("merged", status)
    assert.same({ 'ignore = ["L001", "L002"]' }, lines)
  end)

  it("tolerates a trailing comma in the existing array", function()
    local lines, status = ignore.merge_ignore({ 'ignore = ["L001", ]' }, "L002")
    assert.equals("merged", status)
    assert.same({ 'ignore = ["L001", "L002"]' }, lines)
  end)

  it("is a no-op when the code is already ignored", function()
    local input = { "[lint]", 'ignore = ["L001", "L004"]' }
    local lines, status = ignore.merge_ignore(input, "L004")
    assert.equals("already_ignored", status)
    assert.same({ "[lint]", 'ignore = ["L001", "L004"]' }, lines)
  end)

  it("adds ignore under an existing [lint] table with no ignore key", function()
    local lines, status = ignore.merge_ignore({ "[lint]", 'select = ["L006"]' }, "L004")
    assert.equals("created_lint", status)
    assert.same({ "[lint]", 'ignore = ["L004"]', 'select = ["L006"]' }, lines)
  end)

  it("appends a [lint] block when there is no [lint] table", function()
    local lines, status =
      ignore.merge_ignore({ "[format]", 'indent_style = "tab"' }, "L004")
    assert.equals("created", status)
    assert.same({
      "[format]",
      'indent_style = "tab"',
      "[lint]",
      'ignore = ["L004"]',
    }, lines)
  end)

  it("preserves leading indentation when merging", function()
    local lines, status =
      ignore.merge_ignore({ "[lint]", '  ignore = ["L001"]' }, "L002")
    assert.equals("merged", status)
    assert.same({ "[lint]", '  ignore = ["L001", "L002"]' }, lines)
  end)

  it("ignores an `ignore` key that only appears inside a comment", function()
    -- The comment must not be treated as a real array; with no real ignore key
    -- a fresh [lint] + ignore is created.
    local lines, status = ignore.merge_ignore({ '# ignore = ["L001"]' }, "L004")
    assert.equals("created", status)
    assert.same({ '# ignore = ["L001"]', "[lint]", 'ignore = ["L004"]' }, lines)
  end)

  it("falls back to append for a multi-line ignore array", function()
    local input = {
      "[lint]",
      "ignore = [",
      '  "L001",',
      '  "L002",',
      "]",
    }
    local lines, status = ignore.merge_ignore(input, "L004")
    assert.equals("fallback", status)
    assert.same({
      "[lint]",
      "ignore = [",
      '  "L001",',
      '  "L002",',
      "]",
      'ignore = ["L004"]',
    }, lines)
  end)
end)
