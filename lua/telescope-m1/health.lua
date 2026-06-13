--- telescope-m1: `:checkhealth telescope-m1`.
---
--- The pickers silently depend on several things being present (telescope.nvim,
--- the `m1` extension registered, an attachable m1-lsp client, a resolvable
--- m1-lint binary). When one is missing the user gets an empty picker or a raw
--- error with no guided diagnosis; this reports each with remediation (#35).
local M = {}

local h = vim.health or require("health")
local start = h.start or h.report_start
local ok = h.ok or h.report_ok
local warn = h.warn or h.report_warn
local err = h.error or h.report_error
local info = h.info or h.report_info

--- Classify the lint-rules picker's data source from the resolved m1-lint path.
--- Pure (no vim.health calls) so it is unit-testable; check() renders it.
---@param lint_cmd string?  resolved m1-lint command/path, or nil
---@return "ok"|"warn" level, string msg
function M.lint_status(lint_cmd)
  if lint_cmd then
    return "ok", "m1-lint: " .. lint_cmd .. " (live rule catalogue)"
  end
  return "warn",
    "m1-lint not found — the lint-rules picker falls back to its static catalogue"
end

--- Classify the m1 extension's registration state. Pure for unit-testing.
---@param telescope_ok boolean  whether `require("telescope")` succeeded
---@param registered boolean    whether the `m1` extension is registered
---@return "ok"|"warn"|"error" level, string msg
function M.extension_status(telescope_ok, registered)
  if not telescope_ok then
    return "error", "telescope.nvim not found — telescope-m1 requires it"
  end
  if registered then
    return "ok", "telescope `m1` extension registered"
  end
  return "warn",
    "telescope `m1` extension not loaded — call require('telescope').load_extension('m1')"
end

function M.check()
  start("telescope-m1: telescope.nvim")
  local tok, telescope = pcall(require, "telescope")
  local registered = tok
    and type(telescope.extensions) == "table"
    and telescope.extensions.m1 ~= nil
  local elevel, emsg = M.extension_status(tok, registered)
  if elevel == "ok" then
    ok(emsg)
  elseif elevel == "warn" then
    warn(
      emsg,
      { "Add it to your telescope config or run the load_extension call above." }
    )
  else
    err(emsg, { "Install nvim-telescope/telescope.nvim." })
  end

  start("telescope-m1: m1-lsp (workspace_symbols & components pickers)")
  local client = require("telescope-m1.lsp").find_client()
  if client then
    ok("m1-lsp client active: " .. client.name)
  else
    -- m1-lsp attaches per-buffer, so no client at checkhealth time is normal —
    -- info, not warn, to avoid a false alarm in a non-M1 buffer.
    info(
      "no m1-lsp client attached — open a .m1scr file; the symbol and "
        .. "component pickers need m1-lsp (install via nvim-m1 / :M1Install)"
    )
  end

  start("telescope-m1: m1-lint (lint_rules picker)")
  local llevel, lmsg = M.lint_status(require("telescope-m1.rules").resolve_m1_lint())
  if llevel == "ok" then
    ok(lmsg)
  else
    warn(lmsg, { "Install m1-lint via nvim-m1 (:M1Install) or put it on $PATH." })
  end
end

return M
