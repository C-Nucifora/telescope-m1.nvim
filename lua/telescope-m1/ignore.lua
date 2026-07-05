--- telescope-m1: pure helpers for merging a lint code into a .m1lint.toml
--- `ignore` array without a TOML dependency.
---
--- `.m1lint.toml` keys are TOP-LEVEL — there is no `[lint]` table. A `[lint]`
--- header makes m1-lint reject the whole file (`unknown config key: lint`,
--- exit 2), so this module never writes one; a new top-level `ignore` key is
--- placed before the first table header (e.g. `[severity]`) so it stays
--- top-level rather than being swallowed by that table.
---
--- The logic is line-oriented (no full TOML parse) but, unlike a naive append,
--- it merges into an existing `ignore` array — single- or multi-line — instead
--- of writing a second `ignore` key, which TOML rejects outright as a duplicate
--- key. A genuinely-malformed array (opened but never closed) is left untouched
--- and reported, so the file is never corrupted.
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

-- Parse the quoted codes out of an array body such as `"L001", "L002",`.
-- Returns the list in order.
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
---   * "already_ignored"  — `code` is already in the array; lines unchanged.
---   * "merged"           — `code` was added to an existing single-line array.
---   * "merged_multiline" — `code` was inserted into a multi-line array.
---   * "created"          — a new top-level `ignore = ["code"]` line was added
---                          (before the first table header, or at end of file).
---   * "malformed"        — an `ignore` array was opened but never closed; the
---                          file is left UNCHANGED and the caller should WARN.
---@param lines string[]
---@param code string
---@return string[] new_lines, string status
function M.merge_ignore(lines, code)
  -- Single pass over the top-level region: stop at either the first top-level
  -- `ignore` key or the first table header, whichever comes first (top-level
  -- keys must precede any `[table]`, so a top-level `ignore` is always first).
  local first_table_idx, ignore_idx
  for i, raw in ipairs(lines) do
    local l = strip_comment(raw)
    if l:match("^%s*%[") and l:match("%]") then
      first_table_idx = i
      break
    elseif l:match("^%s*ignore%s*=") then
      ignore_idx = i
      break
    end
  end

  if ignore_idx then
    local raw = lines[ignore_idx]
    -- A single-line array closes its bracket on the same line.
    if strip_comment(raw):match("%]") then
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

    -- Multi-line array: find the closing `]`, collecting the codes on the way.
    local close_idx, last_elem_indent
    for i = ignore_idx, #lines do
      local l = strip_comment(lines[i])
      for _, c in ipairs(parse_codes(l)) do
        if c == code then
          return lines, "already_ignored"
        end
      end
      if l:match('"') then
        last_elem_indent = lines[i]:match("^(%s*)")
      end
      if l:match("%]") then
        close_idx = i
        break
      end
    end
    if not close_idx then
      -- Opened but never closed: appending anything risks a duplicate/garbage
      -- key, so leave the file untouched and let the caller warn.
      return lines, "malformed"
    end
    local indent = last_elem_indent or "\t"
    table.insert(lines, close_idx, ('%s"%s",'):format(indent, code))
    return lines, "merged_multiline"
  end

  -- No `ignore` key yet: add one as a top-level key. It must come before the
  -- first table header (else it lands inside that table), so insert there;
  -- with no table, append at the end of the file.
  local new_line = ('ignore = ["%s"]'):format(code)
  if first_table_idx then
    table.insert(lines, first_table_idx, new_line)
  else
    lines[#lines + 1] = new_line
  end
  return lines, "created"
end

return M
