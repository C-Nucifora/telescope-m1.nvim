-- Minimal init for headless plenary-busted runs.
-- Puts this plugin, plenary and telescope on the runtimepath.
local here =
  vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, "S").source:sub(2)), ":p:h")
local root = vim.fn.fnamemodify(here, ":h")

vim.opt.runtimepath:prepend(root)

local data = vim.fn.stdpath("data") .. "/lazy"
local function add(path)
  if path ~= "" and vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:append(path)
    return true
  end
  return false
end

if not add(vim.env.PLENARY_PATH or "") then
  add(data .. "/plenary.nvim")
end
if not add(vim.env.TELESCOPE_PATH or "") then
  add(data .. "/telescope.nvim")
end

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
