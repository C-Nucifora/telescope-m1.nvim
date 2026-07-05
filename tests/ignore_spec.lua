local ignore = require("telescope-m1.ignore")

describe("telescope-m1.ignore.merge_ignore", function()
  it("writes a top-level ignore (no [lint] table) in an empty file", function()
    -- `.m1lint.toml` keys are top-level; a `[lint]` header makes m1-lint reject
    -- the whole file (`unknown config key: lint`).
    local lines, status = ignore.merge_ignore({}, "L004")
    assert.equals("created", status)
    assert.same({ 'ignore = ["L004"]' }, lines)
  end)

  it("merges into an existing single-line ignore array", function()
    local lines, status = ignore.merge_ignore({ 'ignore = ["L001", "L002"]' }, "L004")
    assert.equals("merged", status)
    assert.same({ 'ignore = ["L001", "L002", "L004"]' }, lines)
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
    local input = { 'ignore = ["L001", "L004"]' }
    local lines, status = ignore.merge_ignore(input, "L004")
    assert.equals("already_ignored", status)
    assert.same({ 'ignore = ["L001", "L004"]' }, lines)
  end)

  it("adds a top-level ignore alongside other top-level keys", function()
    local lines, status = ignore.merge_ignore({ 'select = ["L006"]' }, "L004")
    assert.equals("created", status)
    assert.same({ 'select = ["L006"]', 'ignore = ["L004"]' }, lines)
  end)

  it("inserts the new ignore before the first table header", function()
    -- A bare `ignore` appended after `[severity]` would be read as
    -- `severity.ignore`; it must precede the table to stay top-level.
    local lines, status = ignore.merge_ignore({
      "max-line-length = 100",
      "[severity]",
      'L010 = "error"',
    }, "L004")
    assert.equals("created", status)
    assert.same({
      "max-line-length = 100",
      'ignore = ["L004"]',
      "[severity]",
      'L010 = "error"',
    }, lines)
  end)

  it("preserves leading indentation when merging", function()
    local lines, status = ignore.merge_ignore({ '  ignore = ["L001"]' }, "L002")
    assert.equals("merged", status)
    assert.same({ '  ignore = ["L001", "L002"]' }, lines)
  end)

  it("ignores an `ignore` key that only appears inside a comment", function()
    -- The comment must not be treated as a real array; with no real ignore key
    -- a fresh top-level ignore is created.
    local lines, status = ignore.merge_ignore({ '# ignore = ["L001"]' }, "L004")
    assert.equals("created", status)
    assert.same({ '# ignore = ["L001"]', 'ignore = ["L004"]' }, lines)
  end)

  it("merges into a multi-line ignore array (no duplicate key)", function()
    local input = {
      "ignore = [",
      '  "L001",',
      '  "L002",',
      "]",
    }
    local lines, status = ignore.merge_ignore(input, "L004")
    assert.equals("merged_multiline", status)
    assert.same({
      "ignore = [",
      '  "L001",',
      '  "L002",',
      '  "L004",',
      "]",
    }, lines)
  end)

  it("is a no-op when the code is already in a multi-line array", function()
    local input = {
      "ignore = [",
      '  "L001",',
      "]",
    }
    local lines, status = ignore.merge_ignore(input, "L001")
    assert.equals("already_ignored", status)
    assert.same(input, lines)
  end)

  it("leaves a never-closed array untouched and reports malformed", function()
    local input = {
      "ignore = [",
      '  "L001",',
    }
    local lines, status = ignore.merge_ignore(input, "L004")
    assert.equals("malformed", status)
    assert.same(input, lines)
  end)
end)
