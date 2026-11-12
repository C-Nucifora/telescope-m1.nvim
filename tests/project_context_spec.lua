describe("picker project identity", function()
  local lsp = require("telescope-m1.lsp")
  local original, a, b, dir, buffers

  before_each(function()
    original = { clients = vim.lsp.get_clients, buf = vim.api.nvim_get_current_buf() }
    dir, buffers = vim.fn.tempname(), {}
    for _, name in ipairs({ "a", "b" }) do
      vim.fn.mkdir(dir .. "/" .. name, "p")
      vim.fn.writefile({ "<Project/>" }, dir .. "/" .. name .. "/Project.m1prj")
      buffers[name] = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buffers[name], dir .. "/" .. name .. "/Main.m1scr")
    end
    a = { name = "m1lsp", config = { root_dir = dir .. "/a" } }
    b = { name = "m1lsp", config = { root_dir = dir .. "/b" } }
    vim.lsp.get_clients = function(opts)
      if opts and opts.bufnr == buffers.b then
        return { b }
      end
      if opts and opts.bufnr == buffers.a then
        return { a }
      end
      return { a, b }
    end
    vim.api.nvim_set_current_buf(buffers.b)
  end)

  after_each(function()
    vim.lsp.get_clients = original.clients
    vim.api.nvim_set_current_buf(original.buf)
    for _, buf in pairs(buffers) do
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    vim.fn.delete(dir, "rf")
  end)

  it("selects only a client attached to the invocation buffer", function()
    assert.equals(b, lsp.find_client())
    vim.lsp.get_clients = function(opts)
      if opts and opts.bufnr then
        return {}
      end
      return { a }
    end
    assert.is_nil(lsp.find_client())
  end)

  it("rejects ambiguous attached M1 clients", function()
    vim.lsp.get_clients = function()
      return { a, b }
    end
    assert.is_nil(lsp.find_client())
  end)

  it("keeps delayed symbols tied to their original project", function()
    local handler, requested_buf, entries
    b.request = function(...)
      local args = { ... }
      local offset = vim.fn.has("nvim-0.11") == 1 and 1 or 0
      handler, requested_buf = args[3 + offset], args[4 + offset]
      return true
    end
    a.request = function()
      error("request reached the wrong client")
    end
    lsp.workspace_symbols("", function(result, err)
      assert.is_nil(err)
      entries = result
    end)
    vim.api.nvim_set_current_buf(buffers.a)
    assert.is_function(handler)
    handler(nil, {
      {
        name = "Root.Speed",
        kind = 13,
        location = {
          uri = vim.uri_from_fname(dir .. "/b/Project.m1prj"),
          range = { start = { line = 0, character = 0 } },
        },
      },
    })
    assert.equals(buffers.b, requested_buf)
    assert.equals(dir .. "/b/Project.m1prj", entries[1].project_file)
  end)
end)

describe("call rate project aliases", function()
  local saved, dir, buffer, client, selected_project, definition, select_rate, context
  local pickers = require("telescope.pickers")
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local symbols = require("telescope-m1.symbol_picker")

  before_each(function()
    saved = {
      nvim = package.loaded["nvim-m1"],
      project = package.loaded["nvim-m1.project"],
      clients = vim.lsp.get_clients,
      buffer = vim.api.nvim_get_current_buf(),
      picker = pickers.new,
      close = actions.close,
      replace = actions.select_default.replace,
      selected = state.get_selected_entry,
      symbols = symbols.from_lsp,
    }
    dir = vim.fn.tempname()
    for _, name in ipairs({ "real", "other" }) do
      vim.fn.mkdir(dir .. "/" .. name, "p")
      vim.fn.writefile({ "<Project/>" }, dir .. "/" .. name .. "/Project.m1prj")
    end
    assert(
      (vim.uv or vim.loop).fs_symlink(dir .. "/real", dir .. "/alias", { dir = true })
    )
    buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buffer, dir .. "/alias/Main.m1scr")
    vim.api.nvim_set_current_buf(buffer)
    client = { name = "m1lsp", config = {} }
    vim.lsp.get_clients = function(opts)
      assert.equals(buffer, opts.bufnr)
      return { client }
    end
    package.loaded["nvim-m1"] = { config = {} }
    package.loaded["nvim-m1.project"] = {
      bind_project = function(cfg)
        return cfg
      end,
      project_file = function()
        return selected_project
      end,
      rates = function()
        return { "100Hz" }
      end,
    }
    pickers.new = function(_, value)
      definition = value
      return { find = function() end }
    end
    actions.close = function() end
    actions.select_default.replace = function(_, callback)
      select_rate = callback
    end
    state.get_selected_entry = function()
      return { "100Hz" }
    end
    symbols.from_lsp = function(_, spec)
      context = spec.context
    end
  end)

  after_each(function()
    package.loaded["nvim-m1"], package.loaded["nvim-m1.project"] =
      saved.nvim, saved.project
    vim.lsp.get_clients = saved.clients
    pickers.new, actions.close = saved.picker, saved.close
    actions.select_default.replace, state.get_selected_entry =
      saved.replace, saved.selected
    symbols.from_lsp = saved.symbols
    vim.api.nvim_set_current_buf(saved.buffer)
    if buffer then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
    vim.fn.delete(dir, "rf")
  end)

  it("accepts both alias directions and still rejects another project", function()
    for _, case in ipairs({
      { "real", "real", true },
      { "alias", "real", true },
      { "real", "alias", true },
      { "alias", "alias", true },
      { "other", "real", false },
      { "real", "other", false },
    }) do
      client.config.root_dir = dir .. "/" .. case[1]
      selected_project = dir .. "/" .. case[2] .. "/Project.m1prj"
      definition, context = nil, nil
      require("telescope-m1.pickers.call_rates").open({})
      assert.is_table(definition)
      definition.attach_mappings(0, function() end)
      select_rate()
      assert.equals(case[3], context.client == client, vim.inspect(case))
      assert.equals(client.config.root_dir .. "/Project.m1prj", context.project_file)
    end
  end)
end)
