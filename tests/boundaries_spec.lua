describe("catalogue input boundaries", function()
  for _, name in ipairs({ "rules", "typecheck_rules" }) do
    it(name .. " rejects malformed records without raising", function()
      local module = require("telescope-m1." .. name)
      for _, json in ipairs({
        '{"rules":[null]}',
        '{"rules":[1]}',
        '{"rules":[false]}',
        '{"rules":[{"code":null,"name":"x"}]}',
        '{"rules":[{"code":1,"name":"x"}]}',
        '{"rules":[{"code":"L001","name":[]}]}',
        '{"rules":[{"code":"L001"}]}',
        '{"rules":{"x":{"code":"L001","name":"x"}}}',
        '{"rules":{}}',
      }) do
        local ok, value = pcall(module.parse_catalogue, json)
        assert.is_true(ok, json)
        assert.is_nil(value, json)
      end
    end)
  end
  it("rejects malformed optional lint fields", function()
    for _, field in ipairs({ '"fixable":"yes"', '"severity":false', '"summary":42' }) do
      assert.is_nil(
        require("telescope-m1.rules").parse_catalogue(
          '{"rules":[{"code":"L001","name":"x",' .. field .. "}]}"
        )
      )
    end
  end)
end)

describe("literal backing script navigation", function()
  it("opens percent hash whitespace and pipe paths without expansion", function()
    local picker = require("telescope-m1.pickers.components")
    local state, actions =
      require("telescope.actions.state"), require("telescope.actions")
    local select_entry, close = state.get_selected_entry, actions.close
    local initial = vim.api.nvim_get_current_buf()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local opened = {}
    local ok, err = pcall(function()
      actions.close = function() end
      for _, file in ipairs({
        "with space.m1scr",
        "pipe|name.m1scr",
        "percent%.m1scr",
        "hash#.m1scr",
      }) do
        local path = dir .. "/" .. file
        vim.fn.writefile({ file }, path)
        state.get_selected_entry = function()
          return { value = { kind_label = "Function" }, filename = path, lnum = 1 }
        end
        picker._goto_backing_script(0)
        opened[#opened + 1] = vim.api.nvim_get_current_buf()
        assert.equals(path, vim.api.nvim_buf_get_name(0))
        assert.same({ file }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
      end
    end)
    state.get_selected_entry, actions.close = select_entry, close
    vim.api.nvim_set_current_buf(initial)
    for _, buf in ipairs(opened) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    vim.fn.delete(dir, "rf")
    assert.is_true(ok, err)
  end)
end)

describe("workspace symbol completion", function()
  it("reports rejected requests once even if a late handler runs", function()
    local lsp = require("telescope-m1.lsp")
    local find, handler, count, error_text = lsp.find_client, nil, 0, nil
    local client = {
      request = function(...)
        local args = { ... }
        handler = args[vim.fn.has("nvim-0.11") == 1 and 4 or 3]
        return false
      end,
    }
    lsp.find_client = function()
      return client
    end
    local ok, err = pcall(function()
      lsp.workspace_symbols("", function(_, failure)
        count, error_text = count + 1, failure
      end)
      assert.equals(1, count)
      assert.is_string(error_text)
      handler(nil, {})
      assert.equals(1, count)
    end)
    lsp.find_client = find
    assert.is_true(ok, err)
  end)
end)
