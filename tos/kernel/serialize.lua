-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Serialization          ║
-- ║  Shared Lua table <-> string codec   ║
-- ╚══════════════════════════════════════╝
-- Single source for all serialization in TOS.
-- Replaces duplicated serialize/deserialize in
-- config, users, trust, and protocol modules.

local serialize = {}

-- #SEC M-15 — single depth limit shared by the encoder and decoder. The
-- encoder previously capped at 8 (compact) / 10 (pretty) and SILENTLY
-- replaced anything deeper with "nil", while the decoder accepted up to
-- 64 — so a legitimately-nested packet encoded to a DIFFERENT structure
-- than it decoded back to (silent wire corruption). We align both ends on
-- one limit and the encoder now RAISES on exceeding it instead of
-- truncating, surfacing the problem instead of masking it.
local MAX_DEPTH = 64

-- ============================================================
-- Internal recursive serializer
-- ============================================================

-- #SEC M1 — track tables we've already entered so cycles raise rather
-- than silently truncating at maxDepth (which the old code did, masking
-- self-referential corruption in caller's data).
local function ser(v, depth, maxDepth, pretty, seen)
  -- #SEC M-15 — raise rather than silently truncate to "nil".
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
    seen[v] = nil  -- pop on exit so sibling references to v aren't a "cycle"
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
  return "return " .. ser(tbl, 0, MAX_DEPTH, true)
end

--- Serialize a table to a compact string (for network packets).
-- Output format: "{...}" with no whitespace or "return" prefix.
-- @param tbl table
-- @return string
function serialize.compact(tbl)
  return ser(tbl, 0, MAX_DEPTH, false)
end

-- ============================================================
-- Pure recursive-descent parser for Lua table literals.
-- Does NOT use load() — safe for untrusted data.
-- Handles: strings (%q), numbers, booleans, nil, nested tables.
-- ============================================================

-- Depth cap for the decoder. Anything deeper than this is rejected as
-- malformed. A network packet carrying "{{{{...}}}}" a few thousand
-- levels deep would otherwise recurse until the Lua stack overflows
-- and the coroutine dies — which for the main event loop means the
-- kernel stops pumping signals. Cap generously (protocol packets are
-- never more than a few nests deep; config files stay well under 20).
-- #SEC M-15 — aligned with the encoder's MAX_DEPTH so anything the
-- encoder can produce, the decoder can accept, and vice versa.
local MAX_DECODE_DEPTH = MAX_DEPTH

-- Per-table entry cap. The depth cap stops stack-exhaustion attacks, but a
-- flat table with millions of keys would still thrash GC and exhaust
-- memory. Legitimate payloads (packets, config files, cron/users DB rows)
-- stay well under this; 10k is generous head-room with a clear ceiling.
local MAX_TABLE_ENTRIES = 10000

local function makeParser(str)
  local pos = 1
  local len = #str
  local depth = 0

  local function skipWhitespace()
    while pos <= len do
      local ch = str:byte(pos)
      -- space=32, tab=9, newline=10, CR=13
      if ch == 32 or ch == 9 or ch == 10 or ch == 13 then
        pos = pos + 1
      elseif ch == 45 and str:byte(pos + 1) == 45 then
        -- Lua comment ("--"). Hand-authored serialized files (notably pkg
        -- `package.lua` manifests) carry a comment header before `return`
        -- and inline "-- ..." notes inside the table; the encoder never
        -- emits them, but the decoder must tolerate them or every such
        -- manifest fails to parse ("Invalid number: -") and nothing using
        -- it (pkg discovery/install) can see the package. Skipping comments
        -- is what a real Lua tokenizer does and carries no data, so it
        -- stays safe for untrusted input.
        pos = pos + 2
        -- Long-bracket block comment? --[[ ... ]] or --[=*[ ... ]=*]
        local lvl
        if str:byte(pos) == 91 then          -- "["
          local p, eqs = pos + 1, 0
          while str:byte(p) == 61 do eqs = eqs + 1; p = p + 1 end  -- "="
          if str:byte(p) == 91 then lvl = eqs; pos = p + 1 end     -- second "["
        end
        if lvl then
          local close = "]" .. string.rep("=", lvl) .. "]"
          local s = str:find(close, pos, true)
          pos = s and (s + #close) or (len + 1)   -- unterminated -> consume to EOF
        else
          while pos <= len and str:byte(pos) ~= 10 do pos = pos + 1 end  -- to EOL
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
    -- #SEC L — reject non-finite results. A literal like "1e999" overflows
    -- to inf and "nan" parses to nan; either crashes downstream table.sort
    -- comparators ("invalid order function"). Refuse them as malformed.
    if val ~= val or val == math.huge or val == -math.huge then
      error("non-finite number rejected: " .. numStr)
    end
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
      -- #SEC C17 — refuse duplicate key assignment. A tampered config
      -- could otherwise re-declare `[1] = "good"` ... `[1] = "evil"`
      -- and the second value would silently win, deterministically
      -- replacing the first. Defensive `next` check still O(1).
      if key ~= nil and rawget(tbl, key) ~= nil then
        error("Duplicate key in table literal at position " .. pos)
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
        -- #SEC L — reject non-finite values. A decoded -inf/inf/nan that
        -- later flows into a table.sort comparator raises "invalid order
        -- function" and crashes the sorting code (DoS). Legitimate packets
        -- and config never carry non-finite numbers.
        error("non-finite number (-inf) rejected at position " .. pos)
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
      error("non-finite number (inf) rejected at position " .. pos)  -- #SEC L
    elseif matchKeyword("nan") then
      error("non-finite number (nan) rejected at position " .. pos)  -- #SEC L
    else
      error("Unexpected character '" .. ch .. "' at position " .. pos)
    end
  end

  -- Top-level entry. Skip a leading comment header + an optional `return`
  -- keyword, then read the value. decode() also strips a clean "return "
  -- prefix as a fast path, but when a comment header precedes `return`
  -- that regex can't match — so the parser handles it here too.
  local function parseTop()
    skipWhitespace()
    matchKeyword("return")   -- consumes "return" if present; no-op otherwise
    return parseValue()
  end

  return { parse = parseTop, skipWS = skipWhitespace, pos = function() return pos end }
end

--- Deserialize a string back to a Lua table.
-- Accepts both "return {...}" (from encode) and raw "{...}" (from compact).
-- Uses a pure recursive-descent parser — safe for untrusted data.
-- @param str string
-- @return table|nil, string|nil  (result, error)
-- #SEC C17 — hard byte cap. The decoder applies MAX_TABLE_ENTRIES and
-- MAX_DECODE_DEPTH at parse time, but a 100MB single-string literal in
-- a config file fills memory before either cap fires. 256 KB is well
-- above any legitimate TOS config file (users.dat, cron.db, themes).
local MAX_DECODE_BYTES = 256 * 1024

function serialize.decode(str, opts)
  if not str or str == "" then return nil, "empty input" end
  if type(str) ~= "string" then return nil, "input must be a string" end
  local maxBytes = (opts and opts.maxBytes) or MAX_DECODE_BYTES
  if #str > maxBytes then
    return nil, "input too large (" .. #str .. " > " .. maxBytes .. ")"
  end
  -- #SEC L — be robust about the optional `return` prefix.
  --   * Allow leading whitespace before `return`.
  --   * Require a word boundary after `return` (so `returntrue` isn't
  --     mistaken for `return true`).
  --   * Whitespace-only input rejected as empty.
  --   * Refuse multiple top-level `return ...; return ...` chains by
  --     anchoring the strip to the FIRST return only and not re-stripping.
  if str:match("^%s*$") then return nil, "empty input" end
  local data = str:match("^%s*return%s+(.+)$") or str
  local ok, result = pcall(function()
    local parser = makeParser(data)
    return parser.parse()
  end)
  if not ok then return nil, tostring(result) end
  return result
end

-- ============================================================
-- Convenience: serialized table <-> file
-- ============================================================
-- Used by config / cron / modules to load and persist their on-disk
-- state in one call. Each caller used to inline the same exists/read/
-- decode/encode/write dance.
--
-- @param fs    table: kernel.fs (or anything with exists/readFile/writeFile)
-- @param path  string

--- Read a serialized Lua-table file.
-- Returns nil (no error) if the file does not exist — callers typically
-- want to fall back to defaults in that case rather than treat absence
-- as an error.
function serialize.loadFile(fs, path)
  if not fs or not fs.exists(path) then return nil end
  local data, err = fs.readFile(path)
  if not data then return nil, err end
  return serialize.decode(data)
end

--- Write a table to a file using the pretty-printed encoder.
-- Prefers fs.writeFileAtomic when available so a power cut mid-save can't
-- truncate config/cron/pkg state into an unparseable half-file.
function serialize.saveFile(fs, path, tbl)
  if not fs then return false, "FS not initialized" end
  local data = serialize.encode(tbl)
  if fs.writeFileAtomic then return fs.writeFileAtomic(path, data) end
  return fs.writeFile(path, data)
end

return serialize
