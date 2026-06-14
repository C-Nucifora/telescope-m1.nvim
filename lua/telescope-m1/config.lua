--- telescope-m1: extension configuration.
---
--- Picker data comes from m1-lsp (symbols/components) and m1-lint (rules), so
--- there is little to configure today; this module keeps a single place to add
--- options and is wired to telescope's `extensions.m1` setup table.
local M = {}

---@class TelescopeM1Config
---@field icons "ascii"|"nerd"|false  Symbol-kind icon set for picker rows
--- (#27): "ascii" (default — single ASCII letters, no font requirements),
--- "nerd" (Nerd Font glyphs), or false to drop the icon column content.

---@type TelescopeM1Config
M.options = {
  icons = "ascii",
}

--- Documented values for `icons`. Anything else is a misconfiguration.
local VALID_ICONS = { ascii = true, nerd = true }

--- Merge `ext_config` (from telescope's setup) into the defaults.
---
--- `icons` is the only user-facing knob, so it is validated here: an
--- unrecognised value (a typo like "nerd-fonts", a case-variant like "ASCII",
--- or a stray non-string) would otherwise silently degrade to ascii in
--- `kind_icon` with no feedback. Warn once and reset so the user knows their
--- setting was ignored.
---@param ext_config? table
function M.setup(ext_config)
  M.options = vim.tbl_deep_extend("force", M.options, ext_config or {})

  local icons = M.options.icons
  if icons ~= false and not (type(icons) == "string" and VALID_ICONS[icons]) then
    vim.notify(
      "telescope-m1: unknown icons value "
        .. vim.inspect(icons)
        .. ", using ascii (valid: 'ascii', 'nerd', false)",
      vim.log.levels.WARN
    )
    M.options.icons = "ascii"
  end
end

return M
