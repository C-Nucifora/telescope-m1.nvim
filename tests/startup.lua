-- Exercise dependency plugin startup, which --noplugin unit tests omit.
local failures = {}
local notify = vim.notify
vim.notify = function(message, level, opts)
  if level == vim.log.levels.ERROR then
    failures[#failures + 1] = tostring(message)
  end
  return notify(message, level, opts)
end
local ok, err = pcall(function()
  vim.v.errmsg = ""
  vim.cmd("runtime plugin/telescope.lua")
  assert(vim.g.loaded_telescope == 1, "Telescope plugin did not start")
  assert(vim.v.errmsg == "", vim.v.errmsg)
  require("telescope").setup({})
  require("telescope").load_extension("m1")
  assert(require("telescope").extensions.m1.components)
  if vim.env.M1_REQUIRE_CATALOGUES == "1" then
    for _, name in ipairs({ "m1-lint", "m1-typecheck" }) do
      assert(
        vim.fn.executable(name) == 1,
        "required catalogue binary missing: " .. name
      )
    end
  end
  assert(#failures == 0, table.concat(failures, "\n"))
end)
vim.notify = notify
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
print("Telescope plugin and M1 extension startup passed")
vim.cmd("qa!")
