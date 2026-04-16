-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Serialization         ║
-- ║  Shared Lua table <-> string codec  ║
-- ╚══════════════════════════════════════╝
-- Single source for all serialization in TOS.
-- Replaces duplicated serialize/deserialize in
-- config, users, trust, and protocol modules.

local serialize = {}

-- ============================================================
-- Internal recursive serializer
-- ============================================================

local function ser(v, depth, maxDepth, pretty)
  if depth > maxDepth then return "nil" end
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" then
    return tostring(v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local parts = {}
    local indent = pretty and string.rep("  ", depth + 1) or ""
    local close  = pretty and string.rep("  ", depth) or ""
    local sep    = pretty and ",\n" or ","
    for key, val in pairs(v) do
      local ks
      if type(key) == "string" then
        ks = "[" .. string.format("%q", key) .. "]"
      elseif type(key) == "number" then
        ks = "[" .. key .. "]"
      else
        ks = "[" .. string.format("%q", tostring(key)) .. "]"
      end
      local assign = pretty and " = " or "="
      parts[#parts + 1] = indent .. ks .. assign .. ser(val, depth + 1, maxDepth, pretty)
    end
    if pretty then
      return "{\n" .. table.concat(parts, sep) .. "\n" .. close .. "}"
    else
      return "{" .. table.concat(parts, sep) .. "}"
    end
  end
  return "nil"
end

-- ============================================================
-- Public API
-- ============================================================

--- Serialize a table to a pretty-printed string (for config/data files).
-- Output format: "return { ... }" with indentation.
-- @param tbl table
-- @return string
function serialize.encode(tbl)
  return "return " .. ser(tbl, 0, 10, true)
end

--- Serialize a table to a compact string (for network packets).
-- Output format: "{...}" with no whitespace or "return" prefix.
-- @param tbl table
-- @return string
function serialize.compact(tbl)
  return ser(tbl, 0, 8, false)
end

-- ============================================================
-- Pure recursive-descent parser for Lua table literals.
-- Does NOT use load() — safe for untrusted data.
-- Handles: strings (%q), numbers, booleans, nil, nested tables.
-- ============================================================

local function makeParser(str)
  local pos = 1
  local len = #str

  local function skipWhitespace()
    while pos <= len do
      local ch = str:byte(pos)
      -- space=32, tab=9, newline=10, CR=13
      if ch == 32 or ch == 9 or ch == 10 or ch == 13 then
        pos = pos + 1
      else
        break
      end
    end
  end

  local function peek()
    skipWhitespace()
    return pos <= len and str:sub(pos, pos) or nil
  end

  local function consume(ch)
    skipWhitespace()
    if pos <= len and str:sub(pos, pos) == ch then
      pos = pos + 1
      return true
    end
    return false
  end

  local function expect(ch)
    if not consume(ch) then
      error("Expected '" .. ch .. "' at position " .. pos)
    end
  end

  local function matchKeyword(kw)
    skipWhitespace()
    if str:sub(pos, pos + #kw - 1) == kw then
      -- Ensure it's not a prefix of a longer identifier
      local after = pos + #kw
      if after > len then
        pos = after
        return true
      end
      local ch = str:byte(after)
      -- Not alphanumeric or underscore
      if not ((ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or
              (ch >= 97 and ch <= 122) or ch == 95) then
        pos = after
        return true
      end
    end
    return false
  end

  local parseValue -- forward declaration

  local function parseString()
    skipWhitespace()
    local quote = str:sub(pos, pos)
    if quote ~= '"' and quote ~= "'" then
      error("Expected string at position " .. pos)
    end
    pos = pos + 1
    local parts = {}
    while pos <= len do
      local ch = str:sub(pos, pos)
      if ch == quote then
        pos = pos + 1
        return table.concat(parts)
      elseif ch == "\\" then
        pos = pos + 1
        if pos > len then error("Unterminated escape") end
        local esc = str:sub(pos, pos)
        if esc == "n" then parts[#parts+1] = "\n"
        elseif esc == "t" then parts[#parts+1] = "\t"
        elseif esc == "r" then parts[#parts+1] = "\r"
        elseif esc == "\\" then parts[#parts+1] = "\\"
        elseif esc == '"' then parts[#parts+1] = '"'
        elseif esc == "'" then parts[#parts+1] = "'"
        elseif esc == "a" then parts[#parts+1] = "\a"
        elseif esc == "b" then parts[#parts+1] = "\b"
        elseif esc == "f" then parts[#parts+1] = "\f"
        elseif esc == "v" then parts[#parts+1] = "\v"
        elseif esc == "\n" or esc == "\r" then parts[#parts+1] = "\n"
        elseif esc:match("%d") then
          -- Decimal byte escape: \DDD (up to 3 digits)
          local digits = esc
          for _ = 1, 2 do
            local nx = str:sub(pos + 1, pos + 1)
            if nx:match("%d") then digits = digits .. nx; pos = pos + 1
            else break end
          end
          parts[#parts+1] = string.char(tonumber(digits))
        elseif esc == "x" then
          -- Hex byte escape: \xHH
          local hex = str:sub(pos + 1, pos + 2)
          pos = pos + 2
          parts[#parts+1] = string.char(tonumber(hex, 16))
        else
          parts[#parts+1] = esc  -- Unknown escape, keep literal
        end
        pos = pos + 1
      else
        parts[#parts+1] = ch
        pos = pos + 1
      end
    end
    error("Unterminated string")
  end

  local function parseNumber()
    skipWhitespace()
    local start = pos
    -- Optional sign
    if str:sub(pos, pos) == "-" then pos = pos + 1 end
    -- Hex
    if str:sub(pos, pos + 1) == "0x" or str:sub(pos, pos + 1) == "0X" then
      pos = pos + 2
      while pos <= len and str:sub(pos, pos):match("[%da-fA-F]") do pos = pos + 1 end
    else
      -- Integer/float
      while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
      if pos <= len and str:sub(pos, pos) == "." then
        pos = pos + 1
        while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
      end
      -- Exponent
      if pos <= len and (str:sub(pos, pos) == "e" or str:sub(pos, pos) == "E") then
        pos = pos + 1
        if pos <= len and (str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-") then
          pos = pos + 1
        end
        while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
      end
    end
    -- Also handle inf/nan keywords
    local numStr = str:sub(start, pos - 1)
    local val = tonumber(numStr)
    if not val then error("Invalid number: " .. numStr) end
    return val
  end

  -- Try to read a bare identifier (Lua name): [A-Za-z_][A-Za-z0-9_]*
  -- Returns the identifier string, or nil (restoring pos on failure).
  local function tryBareIdent()
    skipWhitespace()
    local start = pos
    if pos > len then return nil end
    local ch = str:byte(pos)
    -- Must start with letter or underscore
    if not ((ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 95) then
      return nil
    end
    pos = pos + 1
    while pos <= len do
      ch = str:byte(pos)
      if (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or
         (ch >= 97 and ch <= 122) or ch == 95 then
        pos = pos + 1
      else
        break
      end
    end
    local ident = str:sub(start, pos - 1)
    -- Check if followed by '=' (bare key assignment)
    skipWhitespace()
    if pos <= len and str:byte(pos) == 61 then  -- '='
      return ident
    end
    -- Not a bare key assignment — rewind
    pos = start
    return nil
  end

  local function parseTable()
    expect("{")
    local tbl = {}
    local arrayIdx = 1
    while true do
      if consume("}") then return tbl end
      local key, val
      -- Check for [key] = val syntax
      if peek() == "[" then
        consume("[")
        key = parseValue()
        expect("]")
        skipWhitespace()
        expect("=")
        val = parseValue()
      else
        -- Try bare identifier key: name = value
        local ident = tryBareIdent()
        if ident then
          -- We already confirmed '=' follows; consume it
          expect("=")
          key = ident
          val = parseValue()
        else
          -- Implicit array entry: just a value
          val = parseValue()
          key = arrayIdx
          arrayIdx = arrayIdx + 1
        end
      end
      tbl[key] = val
      -- Optional comma/semicolon separator
      if not consume(",") then consume(";") end
    end
  end

  parseValue = function()
    skipWhitespace()
    if pos > len then error("Unexpected end of input") end
    local ch = str:sub(pos, pos)
    if ch == "{" then
      return parseTable()
    elseif ch == '"' or ch == "'" then
      return parseString()
    elseif ch == "-" then
      -- Check if next char is a digit or dot (number) vs keyword like -inf
      local nextCh = pos + 1 <= len and str:sub(pos + 1, pos + 1) or ""
      skipWhitespace()
      if nextCh:match("[%d.]") then
        return parseNumber()
      elseif matchKeyword("-inf") then
        return -math.huge
      else
        return parseNumber()  -- Will error on invalid number
      end
    elseif ch:match("%d") then
      return parseNumber()
    elseif matchKeyword("true") then
      return true
    elseif matchKeyword("false") then
      return false
    elseif matchKeyword("nil") then
      return nil
    elseif matchKeyword("inf") or matchKeyword("math.huge") then
      return math.huge
    elseif matchKeyword("nan") then
      return 0/0
    else
      error("Unexpected character '" .. ch .. "' at position " .. pos)
    end
  end

  return { parse = parseValue, skipWS = skipWhitespace, pos = function() return pos end }
end

--- Deserialize a string back to a Lua table.
-- Accepts both "return {...}" (from encode) and raw "{...}" (from compact).
-- Uses a pure recursive-descent parser — safe for untrusted data.
-- @param str string
-- @return table|nil, string|nil  (result, error)
function serialize.decode(str)
  if not str or str == "" then return nil, "empty input" end
  -- Strip optional "return" prefix
  local data = str:match("^%s*return%s+(.+)$") or str
  local ok, result = pcall(function()
    local parser = makeParser(data)
    return parser.parse()
  end)
  if not ok then return nil, tostring(result) end
  return result
end

return serialize
