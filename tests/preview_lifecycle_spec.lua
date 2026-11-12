local component = require("telescope-m1.component_preview")
local explain = require("telescope-m1.explain_preview")
local rules = require("telescope-m1.rules")

local function pump()
  vim.wait(20, function()
    return false
  end, 5)
end

describe("preview request lifetime", function()
  local saved, win, preview, initial
  before_each(function()
    saved = {
      details = component.fetch_details,
      explain = explain.fetch_explain,
      resolve = rules.resolve_m1_lint,
      nvim = package.loaded["nvim-m1"],
      project = package.loaded["nvim-m1.project"],
    }
    initial = vim.api.nvim_create_buf(false, true)
    win = vim.api.nvim_open_win(initial, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 60,
      height = 10,
      style = "minimal",
    })
  end)
  after_each(function()
    if preview then
      preview:teardown()
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(initial) then
      vim.api.nvim_buf_delete(initial, { force = true })
    end
    preview = nil
    component.fetch_details, explain.fetch_explain = saved.details, saved.explain
    rules.resolve_m1_lint = saved.resolve
    package.loaded["nvim-m1"], package.loaded["nvim-m1.project"] =
      saved.nvim, saved.project
  end)

  local function select(entry)
    preview:preview(entry, { preview_win = win })
    pump()
  end
  local function contents()
    return table.concat(
      vim.api.nvim_buf_get_lines(preview.state.bufnr, 0, -1, false),
      "\n"
    )
  end

  it("repaints the latest component when details arrive", function()
    local finish
    component.fetch_details = function(cb)
      finish = cb
    end
    preview = component.previewer({}, "/fixture/Project.m1prj")
    select({ filename = "/fixture/Project.m1prj", value = { name = "Root.A" } })
    select({ filename = "/fixture/Project.m1prj", value = { name = "Root.B" } })
    finish({ ["Root.A"] = { unit = "rpm" }, ["Root.B"] = { unit = "kPa" } })
    assert.is_truthy(contents():find("kPa", 1, true))
    assert.is_nil(contents():find("rpm", 1, true))
  end)

  it("does not repaint a script selection or a closed component preview", function()
    local finish
    component.fetch_details = function(cb)
      finish = cb
    end
    preview = component.previewer({}, "/fixture/Project.m1prj")
    select({ filename = "/fixture/Project.m1prj", value = { name = "Root.A" } })
    select({ filename = "/fixture/absent.m1scr", value = { name = "Root.Script" } })
    local before = contents()
    finish({ ["Root.A"] = { unit = "rpm" } })
    assert.equals(before, contents())
    preview:teardown()
    preview = nil
    assert.has_no.errors(function()
      finish({})
    end)
  end)

  it("falls back once after real process creation failures", function()
    local missing = vim.fn.tempname() .. "/absent-tool"
    package.loaded["nvim-m1"] = { config = {} }
    package.loaded["nvim-m1.project"] = {
      resolve_cmd = function()
        return missing
      end,
    }
    rules.resolve_m1_lint = function()
      return missing
    end
    local details_calls, explain_calls = 0, 0
    component.fetch_details(function(value)
      details_calls = details_calls + 1
      assert.is_nil(value)
    end, "/fixture/Project.m1prj")
    local job = explain.fetch_explain("L001", function(value)
      explain_calls = explain_calls + 1
      assert.is_nil(value)
    end)
    pump()
    assert.is_nil(job)
    assert.equals(1, details_calls)
    assert.equals(1, explain_calls)
  end)

  it("keeps cancellation ownership through stale completions and teardown", function()
    local requests = {}
    explain.fetch_explain = function(code, cb)
      local request = { code = code, finish = cb, kills = 0 }
      requests[#requests + 1] = request
      return {
        kill = function()
          request.kills = request.kills + 1
        end,
      }
    end
    preview = explain.previewer({})
    local function rule(code)
      select({ value = { code = code, name = code, summary = "fallback " .. code } })
    end
    rule("L001")
    rule("L002")
    requests[1].finish("stale first")
    rule("L001")
    assert.equals(1, requests[1].kills)
    assert.equals(1, requests[2].kills)
    requests[1].finish("stale same code")
    assert.is_nil(contents():find("stale", 1, true))
    local last = requests[3]
    preview:teardown()
    preview = nil
    assert.equals(1, last.kills)
    assert.has_no.errors(function()
      last.finish("after teardown")
    end)
  end)
end)
