--- telescope-m1: lint-rule explanation previewer (#44).
---
--- The lint_rules picker's only rule text was the one-line `summary` column,
--- and `<CR>` opened the rule's GitHub README anchor in a *browser*
--- (`vim.ui.open`) — useless on a headless/remote (SSH) box. m1-lint ships
--- `--explain <CODE>`, a multi-line rationale (what the rule checks, why, the
--- manual reference, and what `--fix` does). This previewer runs the resolved
--- `m1-lint --explain <code>` asynchronously and renders that rationale into
--- the preview buffer, falling back to the static summary when no binary is
--- available. The browser `<CR>` mapping is left unchanged — the previewer is
--- additive. Mirrors component_preview.lua's pure-render + async-fetch split
--- so the logic is unit-testable.
local M = {}

--- Render the preview lines for a rule. When the `m1-lint --explain` text is
--- available it is shown verbatim (split into lines, one trailing newline
--- trimmed); otherwise a static fallback from the rule's own `code`/`name`/
--- `summary` is shown so the previewer is never empty. Pure (no editor calls
--- beyond `vim.split`), so it is unit-testable.
---@param rule { code?: string, name?: string, summary?: string }
---@param text? string  stdout of `m1-lint --explain <code>`, or nil/"" if absent.
---@return string[] lines
function M.render_lines(rule, text)
  if type(text) == "string" and text ~= "" then
    -- Strip a single trailing newline (println! adds one) so the buffer has no
    -- stray blank tail line, then split on the rest.
    local body = text:gsub("\n$", "")
    return vim.split(body, "\n", { plain = true })
  end
  -- Fallback: the data the picker already had.
  local code = rule.code or "?"
  local name = rule.name or ""
  local header = (name ~= "") and (code .. " " .. name) or code
  local lines = { header }
  if type(rule.summary) == "string" and rule.summary ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = rule.summary
  end
  return lines
end

--- Fetch `m1-lint --explain <code>` asynchronously and call `cb(text)` with the
--- rationale, or `cb(nil)` when m1-lint cannot be resolved or exits non-zero /
--- empty (the previewer then renders the static fallback). The callback is
--- always scheduled onto the main loop so it is safe to write a buffer from it.
--- Returns the spawned job handle (with `:kill()`) when a process was started,
--- else nil — so the previewer can cancel an in-flight job on rapid selection
--- movement.
---@param code string  a rule code, e.g. "L004".
---@param cb fun(text: string?)
---@return table?  the vim.system job handle, or nil if nothing was spawned.
function M.fetch_explain(code, cb)
  local rules = require("telescope-m1.rules")
  local bin = rules.resolve_m1_lint()
  if not bin then
    cb(nil) -- no binary (e.g. headless tests, no toolchain): static fallback.
    return nil
  end
  return vim.system({ bin, "--explain", code }, {}, function(res)
    local text = nil
    if res.code == 0 and res.stdout and res.stdout ~= "" then
      text = res.stdout
    end
    vim.schedule(function()
      cb(text)
    end)
  end)
end

--- A buffer previewer for the lint_rules picker: for the selected rule it
--- spawns `m1-lint --explain <code>` and renders the rationale, falling back to
--- the static summary. A previous in-flight job is cancelled when the selection
--- moves, so rapid cursor movement never leaves overlapping jobs racing to
--- write the buffer. The static fallback is written first so the preview is
--- never blank while the async fetch is in flight.
---@param opts table
function M.previewer(opts)
  local previewers = require("telescope.previewers")
  local job ---@type table?  the in-flight vim.system handle, if any.

  --- Write lines into the preview buffer iff it is still the live one for this
  --- request (guards against a late callback clobbering a newer selection).
  local function set_lines(bufnr, lines)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
  end

  return previewers.new_buffer_previewer({
    title = "M1 Lint Rule",
    -- One buffer per rule code: cache the rendered explanation across re-selects.
    get_buffer_by_name = function(_, entry)
      return entry.value and entry.value.code or tostring(entry.ordinal)
    end,
    define_preview = function(self, entry)
      local rule = entry.value or {}
      local bufnr = self.state.bufnr
      -- Cancel any still-running fetch from a previous selection.
      if job then
        pcall(function()
          job:kill(15)
        end)
        job = nil
      end
      -- Static fallback immediately so the pane is never blank.
      set_lines(bufnr, M.render_lines(rule, nil))
      if not rule.code then
        return
      end
      local requested = rule.code
      job = M.fetch_explain(rule.code, function(text)
        job = nil
        if not text then
          return -- keep the static fallback already shown.
        end
        -- Only paint if the selection still points at the rule we fetched.
        local current = self.state.bufnr
        if vim.api.nvim_buf_is_valid(current) then
          local name_ok = pcall(function()
            return vim.api.nvim_buf_get_name(current)
          end)
          if name_ok then
            set_lines(current, M.render_lines(rule, text))
          end
        end
        local _ = requested
      end)
    end,
  })
end

return M
