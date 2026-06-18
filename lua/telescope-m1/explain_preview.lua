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

--- Decide whether a late `--explain` callback may still paint its result.
--- `get_buffer_by_name` keys one preview buffer per rule code, and telescope
--- records that key as the live selection's `self.state.bufname`. So the rule
--- the previewer is *currently* showing is identified by `current_name`; a
--- result fetched for `requested` is stale (the user moved on) iff the two
--- differ. Pure (no editor calls), so it is unit-testable. `current_name` may
--- be nil/empty while telescope is mid-swap — treat that as "not current" so a
--- racing callback never clobbers an indeterminate buffer.
---@param current_name string?  the live selection's buffer key (a rule code).
---@param requested string  the rule code this callback fetched for.
---@return boolean
function M.still_current(current_name, requested)
  return type(current_name) == "string"
    and current_name ~= ""
    and current_name == requested
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
        -- Job cancellation above is best-effort (the pcall swallows a failed
        -- kill, and on_exit can still fire after SIGTERM), so a slow --explain
        -- for an older code can arrive after the user moved on. telescope
        -- records the live selection's buffer key (the rule code, from
        -- get_buffer_by_name) in self.state.bufname, so compare that against
        -- the code we fetched and drop the result on a mismatch.
        if not M.still_current(self.state.bufname, requested) then
          return
        end
        local current = self.state.bufnr
        if vim.api.nvim_buf_is_valid(current) then
          set_lines(current, M.render_lines(rule, text))
        end
      end)
    end,
  })
end

return M
