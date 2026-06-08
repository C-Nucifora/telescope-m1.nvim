--- telescope-m1: pure helpers for merging a lint code into a .m1lint.toml
--- `ignore` array without a TOML dependency.
---
--- The logic is line-oriented (no full TOML parse) but, unlike a naive append,
--- it merges into an existing single-line `ignore = [...]` array instead of
--- writing a second `ignore` key — which TOML parsers resolve last-wins,
--- silently dropping the previously-ignored codes. Genuinely-complex cases
--- (multi-line arrays) fall back to a warn-and-append so the file is never
--- corrupted.
local M = {}

-- Strip an inline `#` comment from a line, ignoring `#` characters that appear
-- inside a double-quoted string. Returns the code portion of the line.
local function strip_comment(line)
  local out = {}
  local in_str = false
  for i = 1, #line do
    local ch = line:sub(i, i)
    if ch == '"' then
      in_str = not in_str
    elseif ch == "#" and not in_str then
      break
    end
    out[#out + 1] = ch
  end
  return table.concat(out)
end

-- Parse the quoted codes out of a single-line array body such as
-- `"L001", "L002",` (the text between `[` and `]`). Returns the list in order.
local function parse_codes(body)
  local codes = {}
  for c in body:gmatch('"([^"]*)"') do
    codes[#codes + 1] = c
  end
  return codes
end

--- Merge `code` into an `ignore = [...]` array within `lines`, purely (no I/O).
---
--- Returns `new_lines, status` where status is one of:
---   * "already_ignored" — `code` is already in the array; lines unchanged.
---   * "merged"          — `code` was added to an existing single-line array.
---   * "created_lint"    — a new `ignore` was added under an existing `[lint]`.
---   * "created"         — a new `[lint]` + `ignore` block was appended.
---   * "fallback"        — the existing `ignore` is too complex to edit safely
---                         (multi-line array), so a fresh `ignore = ["code"]`
---                         line was appended; caller should WARN.
---@param lines string[]
---@param code string
---@return string[] new_lines, string status
function M.merge_ignore(lines, code)
  local ignore_idx, lint_idx
  local saw_multiline_ignore = false
  for i, raw in ipairs(lines) do
    local l = strip_comment(raw)
    if l:match("^%s*%[lint%]%s*$") then
      lint_idx = i
    end
    if l:match("^%s*ignore%s*=") then
      -- A single-line array has both brackets on this line.
      if l:match("%[.*%]") then
        ignore_idx = i
        break
      else
        -- Opening bracket with no close, or a non-array form we won't risk
        -- editing line-by-line.
        saw_multiline_ignore = true
      end
    end
  end

  if ignore_idx then
    local raw = lines[ignore_idx]
    local body = strip_comment(raw):match("%[(.-)%]")
    local existing = parse_codes(body or "")
    for _, c in ipairs(existing) do
      if c == code then
        return lines, "already_ignored"
      end
    end
    existing[#existing + 1] = code
    local quoted = {}
    for _, c in ipairs(existing) do
      quoted[#quoted + 1] = ('"%s"'):format(c)
    end
    -- Preserve any leading indentation on the original line.
    local indent = raw:match("^(%s*)") or ""
    lines[ignore_idx] = ("%signore = [%s]"):format(indent, table.concat(quoted, ", "))
    return lines, "merged"
  end

  -- An existing ignore we can't safely edit: append + let the caller warn.
  if saw_multiline_ignore then
    lines[#lines + 1] = ('ignore = ["%s"]'):format(code)
    return lines, "fallback"
  end

  -- No ignore key at all. Slot one under an existing [lint] table if present,
  -- otherwise append a fresh [lint] block.
  if lint_idx then
    table.insert(lines, lint_idx + 1, ('ignore = ["%s"]'):format(code))
    return lines, "created_lint"
  end

  lines[#lines + 1] = "[lint]"
  lines[#lines + 1] = ('ignore = ["%s"]'):format(code)
  return lines, "created"
end

return M
