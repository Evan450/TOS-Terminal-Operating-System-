local serialize = {}

local MAX_DEPTH = 64

local function ser(v, depth, maxDepth, pretty, seen)

  if depth > maxDepth then
    error("serialization exceeds max depth " .. maxDepth, 0)
  end
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" then
    return tostring(v)
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    seen = seen or {}
    if seen[v] then
      error("cycle detected in table serialization", 0)
    end
    seen[v] = true
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
      parts[#parts + 1] = indent .. ks .. assign .. ser(val, depth + 1, maxDepth, pretty, seen)
    end
    seen[v] = nil
    if pretty then
      return "{\n" .. table.concat(parts, sep) .. "\n" .. close .. "}"
    else
      return "{" .. table.concat(parts, sep) .. "}"
    end
  end
  return "nil"
end

function serialize.encode(tbl)
  return "return " .. ser(tbl, 0, MAX_DEPTH, true)
end

function serialize.compact(tbl)
  return ser(tbl, 0, MAX_DEPTH, false)
end

local MAX_DECODE_DEPTH = MAX_DEPTH

local MAX_TABLE_ENTRIES = 10000

local function makeParser(str)
  local pos = 1
  local len = #str
  local depth = 0

  local function skipWhitespace()
    while pos <= len do
      local ch = str:byte(pos)

      if ch == 32 or ch == 9 or ch == 10 or ch == 13 then
        pos = pos + 1
      elseif ch == 45 and str:byte(pos + 1) == 45 then

        pos = pos + 2

        local lvl
        if str:byte(pos) == 91 then
          local p, eqs = pos + 1, 0
          while str:byte(p) == 61 do eqs = eqs + 1; p = p + 1 end
          if str:byte(p) == 91 then lvl = eqs; pos = p + 1 end
        end
        if lvl then
          local close = "]" .. string.rep("=", lvl) .. "]"
          local s = str:find(close, pos, true)
          pos = s and (s + #close) or (len + 1)
        else
          while pos <= len and str:byte(pos) ~= 10 do pos = pos + 1 end
        end
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

      local after = pos + #kw
      if after > len then
        pos = after
        return true
      end
      local ch = str:byte(after)

      if not ((ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or
              (ch >= 97 and ch <= 122) or ch == 95) then
        pos = after
        return true
      end
    end
    return false
  end

  local parseValue

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

          local digits = esc
          for _ = 1, 2 do
            local nx = str:sub(pos + 1, pos + 1)
            if nx:match("%d") then digits = digits .. nx; pos = pos + 1
            else break end
          end
          parts[#parts+1] = string.char(tonumber(digits))
        elseif esc == "x" then

          local hex = str:sub(pos + 1, pos + 2)
          pos = pos + 2
          parts[#parts+1] = string.char(tonumber(hex, 16))
        else
          parts[#parts+1] = esc
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

    if str:sub(pos, pos) == "-" then pos = pos + 1 end

    if str:sub(pos, pos + 1) == "0x" or str:sub(pos, pos + 1) == "0X" then
      pos = pos + 2
      while pos <= len and str:sub(pos, pos):match("[%da-fA-F]") do pos = pos + 1 end
    else

      while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
      if pos <= len and str:sub(pos, pos) == "." then
        pos = pos + 1
        while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
      end

      if pos <= len and (str:sub(pos, pos) == "e" or str:sub(pos, pos) == "E") then
        pos = pos + 1
        if pos <= len and (str:sub(pos, pos) == "+" or str:sub(pos, pos) == "-") then
          pos = pos + 1
        end
        while pos <= len and str:sub(pos, pos):match("%d") do pos = pos + 1 end
      end
    end

    local numStr = str:sub(start, pos - 1)
    local val = tonumber(numStr)
    if not val then error("Invalid number: " .. numStr) end

    if val ~= val or val == math.huge or val == -math.huge then
      error("non-finite number rejected: " .. numStr)
    end
    return val
  end

  local function tryBareIdent()
    skipWhitespace()
    local start = pos
    if pos > len then return nil end
    local ch = str:byte(pos)

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

    skipWhitespace()
    if pos <= len and str:byte(pos) == 61 then
      return ident
    end

    pos = start
    return nil
  end

  local function parseTable()
    expect("{")
    depth = depth + 1
    if depth > MAX_DECODE_DEPTH then
      error("Max table nesting depth exceeded (" .. MAX_DECODE_DEPTH .. ")")
    end
    local tbl = {}
    local arrayIdx = 1
    local entries = 0
    while true do
      if consume("}") then depth = depth - 1; return tbl end
      entries = entries + 1
      if entries > MAX_TABLE_ENTRIES then
        error("Max table entries exceeded (" .. MAX_TABLE_ENTRIES .. ")")
      end
      local key, val

      if peek() == "[" then
        consume("[")
        key = parseValue()
        expect("]")
        skipWhitespace()
        expect("=")
        val = parseValue()
      else

        local ident = tryBareIdent()
        if ident then

          expect("=")
          key = ident
          val = parseValue()
        else

          val = parseValue()
          key = arrayIdx
          arrayIdx = arrayIdx + 1
        end
      end

      if key ~= nil and rawget(tbl, key) ~= nil then
        error("Duplicate key in table literal at position " .. pos)
      end
      tbl[key] = val

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

      local nextCh = pos + 1 <= len and str:sub(pos + 1, pos + 1) or ""
      skipWhitespace()
      if nextCh:match("[%d.]") then
        return parseNumber()
      elseif matchKeyword("-inf") then

        error("non-finite number (-inf) rejected at position " .. pos)
      else
        return parseNumber()
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
      error("non-finite number (inf) rejected at position " .. pos)
    elseif matchKeyword("nan") then
      error("non-finite number (nan) rejected at position " .. pos)
    else
      error("Unexpected character '" .. ch .. "' at position " .. pos)
    end
  end

  local function parseTop()
    skipWhitespace()
    matchKeyword("return")
    return parseValue()
  end

  return { parse = parseTop, skipWS = skipWhitespace, pos = function() return pos end }
end

local MAX_DECODE_BYTES = 256 * 1024

function serialize.decode(str, opts)
  if not str or str == "" then return nil, "empty input" end
  if type(str) ~= "string" then return nil, "input must be a string" end
  local maxBytes = (opts and opts.maxBytes) or MAX_DECODE_BYTES
  if #str > maxBytes then
    return nil, "input too large (" .. #str .. " > " .. maxBytes .. ")"
  end

  if str:match("^%s*$") then return nil, "empty input" end
  local data = str:match("^%s*return%s+(.+)$") or str
  local ok, result = pcall(function()
    local parser = makeParser(data)
    return parser.parse()
  end)
  if not ok then return nil, tostring(result) end
  return result
end

function serialize.loadFile(fs, path)
  if not fs or not fs.exists(path) then return nil end
  local data, err = fs.readFile(path)
  if not data then return nil, err end
  return serialize.decode(data)
end

function serialize.saveFile(fs, path, tbl)
  if not fs then return false, "FS not initialized" end
  local data = serialize.encode(tbl)
  if fs.writeFileAtomic then return fs.writeFileAtomic(path, data) end
  return fs.writeFile(path, data)
end

return serialize
