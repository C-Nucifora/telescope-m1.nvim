--- Merge a top-level lint ignore array while preserving its text and comments.
--- Unsupported string/key syntax is refused without changing the input.
local M = {}

local function skip_space(text, at)
  while at <= #text do
    local ch = text:sub(at, at)
    if ch:match("%s") then
      at = at + 1
    elseif ch == "#" then
      at = text:find("\n", at, true) or (#text + 1)
    else
      break
    end
  end
  return at
end

local function quoted(text, at, escapes)
  local quote = text:sub(at, at)
  if text:sub(at, at + 2) == quote:rep(3) then
    return nil
  end
  local start = at
  at = at + 1
  while at <= #text do
    local ch = text:sub(at, at)
    if ch == quote then
      return text:sub(start + 1, at - 1), at + 1
    end
    if ch == "\n" or ch == "\r" then
      return nil
    end
    if ch == "\\" and quote == '"' then
      if not escapes then
        return nil
      end
      at = at + 1
    end
    at = at + 1
  end
end

-- Find the next statement without mistaking an array element for a top-level key.
local function value_end(text, at)
  local stack = {}
  while at <= #text do
    local ch = text:sub(at, at)
    if ch == '"' or ch == "'" then
      local _, next_at = quoted(text, at, true)
      if not next_at then
        return nil
      end
      at = next_at
    elseif ch == "#" then
      at = text:find("\n", at, true) or (#text + 1)
    elseif ch == "\n" and #stack == 0 then
      return at
    elseif ch == "[" or ch == "{" then
      stack[#stack + 1] = ch == "[" and "]" or "}"
      at = at + 1
    elseif ch == "]" or ch == "}" then
      if table.remove(stack) ~= ch then
        return nil
      end
      at = at + 1
    else
      at = at + 1
    end
  end
  if #stack == 0 then
    return at
  end
end

local function parse_array(text, at, finish)
  at = skip_space(text, at)
  if text:sub(at, at) ~= "[" then
    return nil
  end
  local values, last_end, comma = {}, nil, false
  at = skip_space(text, at + 1)
  while at < finish do
    local ch = text:sub(at, at)
    if ch == "]" then
      if skip_space(text:sub(1, finish - 1), at + 1) ~= finish then
        return nil
      end
      return { values = values, last_end = last_end, comma = comma, close = at }
    end
    if #values > 0 and not comma then
      return nil
    end
    if ch ~= '"' and ch ~= "'" then
      return nil
    end
    local value, next_at = quoted(text, at, false)
    if not next_at then
      return nil
    end
    values[#values + 1] = value
    last_end = next_at - 1
    at = skip_space(text, next_at)
    comma = text:sub(at, at) == ","
    if comma then
      at = skip_space(text, at + 1)
    end
  end
end

---@param lines string[]
---@param code string
---@return string[] new_lines, string status
function M.merge_ignore(lines, code)
  if type(code) ~= "string" or not code:match("^L%d+$") then
    return lines, "malformed"
  end
  local text = table.concat(lines, "\n")
  local at, found, first_table = 1, nil, nil
  while true do
    at = skip_space(text, at)
    if at > #text then
      break
    end
    local ch = text:sub(at, at)
    if ch == "[" then
      -- .m1lint.toml has one supported table. Refuse unknown headers rather
      -- than risk introducing a key that conflicts with an existing table.
      if not text:sub(at):match("^%[%s*[\"']?severity[\"']?%s*%]") then
        return lines, "malformed"
      end
      first_table = at
      break
    end
    local key, next_at
    if ch == '"' or ch == "'" then
      key, next_at = quoted(text, at, false)
    else
      local relative
      key, relative = text:sub(at):match("^([%w_.%-]+)()")
      if relative then
        next_at = at + relative - 1
      end
    end
    if not next_at then
      return lines, "malformed"
    end
    local eq = text:find("[^ \t]", next_at)
    if not eq or text:sub(eq, eq) ~= "=" then
      return lines, "malformed"
    end
    local finish = value_end(text, eq + 1)
    if not finish then
      return lines, "malformed"
    end
    if key == "ignore" then
      if found then
        return lines, "malformed"
      end
      found = parse_array(text, eq + 1, finish)
      if not found then
        return lines, "malformed"
      end
    elseif key:match("^ignore%.") then
      return lines, "malformed"
    end
    at = finish + 1
  end

  if not found then
    local result = vim.deepcopy(lines)
    local index = first_table
        and select(2, text:sub(1, first_table - 1):gsub("\n", "")) + 1
      or #result + 1
    table.insert(result, index, ('ignore = ["%s"]'):format(code))
    return result, "created"
  end
  for _, value in ipairs(found.values) do
    if value == code then
      return lines, "already_ignored"
    end
  end
  local close_line = text:sub(1, found.close - 1):match(".*\n()") or 1
  local multiline = close_line > 1
    and text:sub(close_line, found.close - 1):match("^%s*$")
  local insertion, insert_at
  if multiline then
    local prefix = found.last_end and text:sub(1, found.last_end) or ""
    local indent = prefix:match("\n([ \t]*)[^\n]*$") or "\t"
    insertion, insert_at = indent .. '"' .. code .. '",\n', close_line
  else
    local separator = #found.values == 0 and "" or (found.comma and "" or ", ")
    insertion, insert_at = separator .. '"' .. code .. '"', found.close
  end
  text = text:sub(1, insert_at - 1) .. insertion .. text:sub(insert_at)
  if multiline and found.last_end and not found.comma then
    text = text:sub(1, found.last_end) .. "," .. text:sub(found.last_end + 1)
  end
  return vim.split(text, "\n", { plain = true }),
    multiline and "merged_multiline" or "merged"
end

return M
