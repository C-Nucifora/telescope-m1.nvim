local ignore = require("telescope-m1.ignore")

describe("lint ignore preserves accepted TOML", function()
  local fixtures = {
    {
      input = { "ignore = [", '  "L001" # keep', "]" },
      expected = { "ignore = [", '  "L001", # keep', '  "L002",', "]" },
    },
    {
      input = { "ignore = ['L001'] # keep" },
      expected = { "ignore = ['L001', \"L002\"] # keep" },
    },
    { input = { '"ignore" = ["L001"]' }, expected = { '"ignore" = ["L001", "L002"]' } },
    {
      input = { "'ignore' = [", "  'L001'] # keep" },
      expected = { "'ignore' = [", "  'L001', \"L002\"] # keep" },
    },
    {
      input = { "select = [", ' "L001", "L002",', "]", 'ignore = ["L001"]' },
      expected = { "select = [", ' "L001", "L002",', "]", 'ignore = ["L001", "L002"]' },
    },
  }
  for i, fixture in ipairs(fixtures) do
    it("preserves values and comments in fixture " .. i, function()
      local original = vim.deepcopy(fixture.input)
      local result, status = ignore.merge_ignore(fixture.input, "L002")
      assert.is_not.equal("malformed", status)
      assert.same(fixture.expected, result)
      assert.same(original, fixture.input, "pure helper must not mutate its input")
      local again, duplicate = ignore.merge_ignore(result, "L002")
      assert.equals("already_ignored", duplicate)
      assert.same(result, again)
    end)
  end
  it("refuses ambiguous syntax without changing any input", function()
    for _, input in ipairs({
      { 'ignore = ["L001" "L003"]' },
      { '"ign\\u006fre" = ["L001"]' },
      { 'ignore = ["L\\u0030001"]' },
      { 'note = """', 'ignore = ["L001"]', '"""' },
      { 'ignore = "not an array"' },
      { 'ignore = ["L001"', "]", 'ignore = ["L003"]' },
    }) do
      local original = vim.deepcopy(input)
      local result, status = ignore.merge_ignore(input, "L002")
      assert.equals("malformed", status)
      assert.same(original, result)
      assert.same(original, input)
    end
  end)
  it(
    "writes through the real picker and produces configs accepted by m1-lint",
    function()
      if vim.fn.executable("m1-lint") ~= 1 then
        pending("requires m1-lint")
        return
      end
      local picker = require("telescope-m1.pickers.lint_rules")
      local original_buf, notify = vim.api.nvim_get_current_buf(), vim.notify
      local dir, buf = vim.fn.tempname(), vim.api.nvim_create_buf(false, true)
      vim.fn.mkdir(dir, "p")
      vim.api.nvim_buf_set_name(buf, dir .. "/Main.m1scr")
      vim.api.nvim_set_current_buf(buf)
      vim.notify = function() end
      local ok, err = pcall(function()
        vim.fn.writefile({}, dir .. "/Main.m1scr")
        for _, fixture in ipairs(fixtures) do
          vim.fn.writefile(fixture.input, dir .. "/.m1lint.toml")
          picker._ignore_in_config("L002")
          assert.same(fixture.expected, vim.fn.readfile(dir .. "/.m1lint.toml"))
          local result = vim
            .system({
              "m1-lint",
              "--jobs",
              "1",
              "--config",
              dir .. "/.m1lint.toml",
              dir .. "/Main.m1scr",
            }, { text = true })
            :wait(5000)
          assert.equals(0, result.code, result.stderr)
        end
        local unsupported = { 'ignore = ["\\u004c001"]' }
        vim.fn.writefile(unsupported, dir .. "/.m1lint.toml")
        picker._ignore_in_config("L002")
        assert.same(unsupported, vim.fn.readfile(dir .. "/.m1lint.toml"))
      end)
      vim.notify = notify
      vim.api.nvim_set_current_buf(original_buf)
      vim.api.nvim_buf_delete(buf, { force = true })
      vim.fn.delete(dir, "rf")
      assert.is_true(ok, err)
    end
  )
end)

describe("ignore action and unsaved config buffers", function()
  it("refuses conflicting writes including through a directory alias", function()
    local picker = require("telescope-m1.pickers.lint_rules")
    local original_buf, notify = vim.api.nvim_get_current_buf(), vim.notify
    local dir, buffers, notices = vim.fn.tempname(), {}, {}
    vim.fn.mkdir(dir .. "/real", "p")
    local config = dir .. "/real/.m1lint.toml"
    local disk = { 'ignore = ["L001"]' }
    local edited = { 'ignore = ["L001", "L003"]' }
    vim.fn.writefile(disk, config)
    local config_buf = vim.fn.bufadd(config)
    buffers[#buffers + 1] = config_buf
    vim.fn.bufload(config_buf)
    vim.api.nvim_buf_set_lines(config_buf, 0, -1, false, edited)
    vim.notify = function(msg)
      notices[#notices + 1] = msg
    end
    local ok, err = pcall(function()
      local paths = { dir .. "/real" }
      if vim.uv.fs_symlink(dir .. "/real", dir .. "/alias", { dir = true }) then
        paths[#paths + 1] = dir .. "/alias"
      end
      for index, path in ipairs(paths) do
        local script = vim.api.nvim_create_buf(false, true)
        buffers[#buffers + 1] = script
        vim.api.nvim_buf_set_name(script, path .. "/Main" .. index .. ".m1scr")
        vim.api.nvim_set_current_buf(script)
        picker._ignore_in_config("L002")
        assert.same(disk, vim.fn.readfile(config))
        assert.same(edited, vim.api.nvim_buf_get_lines(config_buf, 0, -1, false))
        assert.is_truthy(notices[#notices]:find("unsaved", 1, true))
      end
      vim.api.nvim_buf_set_lines(config_buf, 0, -1, false, disk)
      vim.bo[config_buf].modified = false
      picker._ignore_in_config("L002")
      assert.is_truthy(table.concat(vim.fn.readfile(config)):find("L002", 1, true))
    end)
    vim.notify = notify
    vim.api.nvim_set_current_buf(original_buf)
    for _, buf in ipairs(buffers) do
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.fn.delete(dir, "rf")
    assert.is_true(ok, err)
  end)
end)
