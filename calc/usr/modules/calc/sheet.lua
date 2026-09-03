-- ╔══════════════════════════════════════════════════════════════╗
-- ║  calc — the sheet MODEL + FORMULA ENGINE (pure, no I/O)      ║
-- ║                                                              ║
-- ║  A spreadsheet is mostly a small language implementation, so ║
-- ║  all of it lives here as value-in/value-out code and         ║
-- ║  unit-tests off-box; init.lua is drawing + keys only.        ║
-- ║                                                              ║
-- ║  WHY A REAL PARSER (and not `load`): the obvious way to      ║
-- ║  evaluate "=A1*2+SUM(B1:B9)" is to rewrite it into Lua and   ║
-- ║  load() it. TOS refuses to do that. Package code doesn't     ║
-- ║  even get `load` unless its manifest asks for the cap, and a ║
-- ║  spreadsheet whose CELLS are executable is a code-execution  ║
-- ║  surface disguised as a data file — one shared .calc and the ║
-- ║  sandbox is the only thing between a formula and the         ║
-- ║  machine. (The Python reference this is modelled on uses     ║
-- ║  eval() behind a character-whitelist "sanitizer"; that is    ║
-- ║  exactly the pattern we don't want.) So: a tokenizer and a   ║
-- ║  recursive-descent parser over a fixed grammar. Nothing a    ║
-- ║  cell can contain is ever executed — the worst a hostile     ║
-- ║  formula can do is evaluate to #ERR.                         ║
-- ║                                                              ║
-- ║  Errors are TABLES ({ e = "#DIV/0!" }), not strings, so a    ║
-- ║  text cell that happens to start with "#" can never be       ║
-- ║  mistaken for an error and propagated.                       ║
-- ╚══════════════════════════════════════════════════════════════╝

local S = {}

S.MAX_COLS = 26 * 3      -- A..Z, AA..AZ, BA..BZ — plenty for an 80-col screen
S.MAX_ROWS = 512
S.MAX_DEPTH = 32         -- reference-chain depth guard (belt with the cycle brace)

-- ============================================================
-- Errors
-- ============================================================

local function err(code) return { e = code } end
local function isErr(v) return type(v) == "table" and v.e ~= nil end
S.err, S.isErr = err, isErr

S.E_CYCLE = "#CYCLE!"
S.E_DIV   = "#DIV/0!"
S.E_NAME  = "#NAME?"
S.E_REF   = "#REF!"
S.E_VALUE = "#VALUE!"
S.E_SYNTAX = "#SYNTAX!"
S.E_DEPTH = "#DEPTH!"

-- ============================================================
-- Column / cell addressing
-- ============================================================

--- 1 -> "A", 26 -> "Z", 27 -> "AA". Pure.
function S.colName(n)
  if type(n) ~= "number" or n < 1 then return "?" end
  local name = ""
  while n > 0 do
    local rem = (n - 1) % 26
    name = string.char(65 + rem) .. name
    n = math.floor((n - 1) / 26)
  end
  return name
end

--- "A" -> 1, "AA" -> 27. Returns nil on junk. Pure.
function S.colIndex(s)
  if type(s) ~= "string" or s == "" then return nil end
  s = s:upper()
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 65 or b > 90 then return nil end
    n = n * 26 + (b - 64)
  end
  return n
end

--- "B3" -> (2, 3). Returns nil when it isn't a reference. Pure.
function S.parseRef(s)
  if type(s) ~= "string" then return nil end
  local col, row = s:match("^(%a+)(%d+)$")
  if not col then return nil end
  local c = S.colIndex(col)
  local r = tonumber(row)
  if not c or not r or r < 1 then return nil end
  if c > S.MAX_COLS or r > S.MAX_ROWS then return nil end
  return c, r
end

function S.refName(c, r) return S.colName(c) .. tostring(r) end

-- Internal cell key. A string key keeps the store sparse (a 26x512 grid
-- of nils would otherwise cost real memory on a 192 KB machine).
local function key(c, r) return c .. ":" .. r end
S._key = key

-- ============================================================
-- Sheet construction
-- ============================================================

function S.new()
  return {
    cells = {},          -- ["c:r"] = raw string as typed
    cols  = 8,           -- logical extent (grows as cells are set)
    rows  = 20,
  }
end

--- Store a cell's RAW text ("" / nil clears it). Mutates; returns the sheet.
function S.set(sh, c, r, raw)
  if c < 1 or r < 1 or c > S.MAX_COLS or r > S.MAX_ROWS then return sh end
  local k = key(c, r)
  if raw == nil or raw == "" then
    sh.cells[k] = nil
  else
    sh.cells[k] = tostring(raw)
    if c > sh.cols then sh.cols = c end
    if r > sh.rows then sh.rows = r end
  end
  return sh
end

--- The raw text of a cell ("" when empty). Pure.
function S.raw(sh, c, r) return sh.cells[key(c, r)] or "" end

-- ============================================================
-- Tokenizer
-- ============================================================
-- Token = { t = "num"|"str"|"ref"|"range"|"name"|"op"|"("|")"|",",
--           v = <value> }

local OPS2 = { ["<="] = true, [">="] = true, ["<>"] = true }
local OPS1 = { ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true,
               ["%"] = true, ["^"] = true, ["="] = true, ["<"] = true,
               [">"] = true }

function S.tokenize(src)
  local toks, i, n = {}, 1, #src
  while i <= n do
    local ch = src:sub(i, i)
    if ch == " " or ch == "\t" then
      i = i + 1
    elseif ch == '"' then
      -- String literal. Doubled quotes ("") escape a quote, as in the
      -- spreadsheets people already know.
      local buf, j = {}, i + 1
      while j <= n do
        local c2 = src:sub(j, j)
        if c2 == '"' then
          if src:sub(j + 1, j + 1) == '"' then buf[#buf + 1] = '"'; j = j + 2
          else break end
        else
          buf[#buf + 1] = c2; j = j + 1
        end
      end
      if j > n then return nil, S.E_SYNTAX end      -- unterminated
      toks[#toks + 1] = { t = "str", v = table.concat(buf) }
      i = j + 1
    elseif ch:match("%d") or (ch == "." and src:sub(i + 1, i + 1):match("%d")) then
      local numStr = src:match("^%d*%.?%d+", i) or src:match("^%d+", i)
      -- Scientific notation, e.g. 1e3 / 2.5E-4.
      local expPart = src:match("^[eE][%+%-]?%d+", i + #numStr)
      if expPart then numStr = numStr .. expPart end
      toks[#toks + 1] = { t = "num", v = tonumber(numStr) }
      i = i + #numStr
    elseif ch:match("%a") then
      local word = src:match("^%a[%w_%.]*", i)
      local after = i + #word
      -- A bare A1 is a ref; A1:B3 is a range; anything else is a name
      -- (function or a bare word like TRUE).
      local c1, r1 = S.parseRef(word)
      if c1 and src:sub(after, after) == ":" then
        local word2 = src:match("^%a+%d+", after + 1)
        -- NOT `word2 and S.parseRef(word2)`: an `and` expression yields
        -- only the FIRST return value, which silently dropped the range's
        -- end ROW and made every range formula blow up in numList.
        local c2, r2
        if word2 then c2, r2 = S.parseRef(word2) end
        if c2 then
          toks[#toks + 1] = { t = "range", c1 = c1, r1 = r1, c2 = c2, r2 = r2 }
          i = after + 1 + #word2
        else
          return nil, S.E_REF
        end
      elseif c1 then
        toks[#toks + 1] = { t = "ref", c = c1, r = r1 }
        i = after
      else
        toks[#toks + 1] = { t = "name", v = word:upper() }
        i = after
      end
    else
      local two = src:sub(i, i + 1)
      if OPS2[two] then
        toks[#toks + 1] = { t = "op", v = two }; i = i + 2
      elseif OPS1[ch] then
        toks[#toks + 1] = { t = "op", v = ch }; i = i + 1
      elseif ch == "(" or ch == ")" or ch == "," then
        toks[#toks + 1] = { t = ch }; i = i + 1
      else
        return nil, S.E_SYNTAX
      end
    end
  end
  return toks
end

-- ============================================================
-- Parser (recursive descent) -> AST
-- ============================================================
-- Precedence, loosest first:
--   comparison  = <> < > <= >=      (left)
--   add/sub     + -                 (left)
--   mul/div/mod * / %               (left)
--   unary       - +
--   power       ^                   (right)

local function parser(toks)
  local p = { toks = toks, i = 1 }
  function p:peek() return self.toks[self.i] end
  function p:next() local t = self.toks[self.i]; self.i = self.i + 1; return t end
  function p:accept(tt, v)
    local t = self:peek()
    if t and t.t == tt and (v == nil or t.v == v) then return self:next() end
  end
  return p
end

local parseExpr   -- forward

local function parsePrimary(p)
  local t = p:next()
  if not t then return nil, S.E_SYNTAX end
  if t.t == "num" then return { k = "num", v = t.v } end
  if t.t == "str" then return { k = "str", v = t.v } end
  if t.t == "ref" then return { k = "ref", c = t.c, r = t.r } end
  if t.t == "range" then
    return { k = "range", c1 = t.c1, r1 = t.r1, c2 = t.c2, r2 = t.r2 }
  end
  if t.t == "(" then
    local node, e = parseExpr(p)
    if not node then return nil, e end
    if not p:accept(")") then return nil, S.E_SYNTAX end
    return node
  end
  if t.t == "name" then
    if p:accept("(") then
      local args = {}
      if not p:accept(")") then
        while true do
          local a, e = parseExpr(p)
          if not a then return nil, e end
          args[#args + 1] = a
          if p:accept(",") then
          elseif p:accept(")") then break
          else return nil, S.E_SYNTAX end
        end
      end
      return { k = "call", name = t.v, args = args }
    end
    -- Bare words: the two booleans, otherwise an unknown name.
    if t.v == "TRUE" then return { k = "num", v = 1 } end
    if t.v == "FALSE" then return { k = "num", v = 0 } end
    return { k = "err", v = S.E_NAME }
  end
  if t.t == "op" and (t.v == "-" or t.v == "+") then
    local node, e = parsePrimary(p)
    if not node then return nil, e end
    return { k = "unary", op = t.v, a = node }
  end
  return nil, S.E_SYNTAX
end

local function parsePower(p)
  local base, e = parsePrimary(p)
  if not base then return nil, e end
  local t = p:peek()
  if t and t.t == "op" and t.v == "^" then
    p:next()
    local rhs, e2 = parsePower(p)          -- right-associative
    if not rhs then return nil, e2 end
    return { k = "bin", op = "^", a = base, b = rhs }
  end
  return base
end

local function parseUnary(p)
  local t = p:peek()
  if t and t.t == "op" and (t.v == "-" or t.v == "+") then
    p:next()
    local a, e = parseUnary(p)
    if not a then return nil, e end
    return { k = "unary", op = t.v, a = a }
  end
  return parsePower(p)
end

local function parseBinLevel(p, ops, sub)
  local left, e = sub(p)
  if not left then return nil, e end
  while true do
    local t = p:peek()
    if t and t.t == "op" and ops[t.v] then
      p:next()
      local right, e2 = sub(p)
      if not right then return nil, e2 end
      left = { k = "bin", op = t.v, a = left, b = right }
    else
      return left
    end
  end
end

local MULOPS = { ["*"] = true, ["/"] = true, ["%"] = true }
local ADDOPS = { ["+"] = true, ["-"] = true }
local CMPOPS = { ["="] = true, ["<>"] = true, ["<"] = true, [">"] = true,
                 ["<="] = true, [">="] = true }

local function parseMul(p) return parseBinLevel(p, MULOPS, parseUnary) end
local function parseAdd(p) return parseBinLevel(p, ADDOPS, parseMul) end
parseExpr = function(p) return parseBinLevel(p, CMPOPS, parseAdd) end

--- Parse a formula body (no leading "="). Returns (ast) or (nil, errCode).
function S.parse(src)
  local toks, terr = S.tokenize(src)
  if not toks then return nil, terr end
  if #toks == 0 then return nil, S.E_SYNTAX end
  local p = parser(toks)
  local ast, e = parseExpr(p)
  if not ast then return nil, e end
  if p:peek() then return nil, S.E_SYNTAX end     -- trailing junk
  return ast
end

-- ============================================================
-- Evaluation
-- ============================================================

local function toNum(v)
  if type(v) == "number" then return v end
  if type(v) == "boolean" then return v and 1 or 0 end
  if type(v) == "string" then
    if v == "" then return 0 end
    return tonumber(v)                            -- nil when not numeric
  end
  if v == nil then return 0 end                   -- an empty cell is 0
  return nil
end
S.toNum = toNum

local function toStr(v)
  if v == nil then return "" end
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then
      return string.format("%d", v)
    end
    return tostring(v)
  end
  return tostring(v)
end
S.toStr = toStr

-- Flatten call arguments into a numeric list, expanding ranges. Errors
-- inside the range propagate (a SUM over a broken cell is broken).
local function numList(ctx, args, evalNode)
  local out = {}
  for _, a in ipairs(args) do
    if a.k == "range" then
      for c = math.min(a.c1, a.c2), math.max(a.c1, a.c2) do
        for r = math.min(a.r1, a.r2), math.max(a.r1, a.r2) do
          local v = ctx.get(c, r)
          if isErr(v) then return nil, v end
          local n = toNum(v)
          -- Text and blanks are SKIPPED (spreadsheet convention) so a
          -- label row inside a range doesn't poison the sum.
          if n ~= nil and not (v == nil or v == "") then out[#out + 1] = n end
        end
      end
    else
      local v = evalNode(a)
      if isErr(v) then return nil, v end
      local n = toNum(v)
      if n == nil then return nil, err(S.E_VALUE) end
      out[#out + 1] = n
    end
  end
  return out
end

-- Range-aware COUNT: counts numeric entries only.
local FUNCS = {}

local function fnAgg(name, fold, init, post)
  FUNCS[name] = function(ctx, args, evalNode)
    local list, e = numList(ctx, args, evalNode)
    if not list then return e end
    if #list == 0 then return post and post(init, 0) or init end
    local acc = init
    for _, v in ipairs(list) do acc = fold(acc, v) end
    return post and post(acc, #list) or acc
  end
end

fnAgg("SUM", function(a, b) return a + b end, 0)
fnAgg("AVERAGE", function(a, b) return a + b end, 0,
  function(acc, n) if n == 0 then return err(S.E_DIV) end return acc / n end)
FUNCS.AVG = function(...) return FUNCS.AVERAGE(...) end
FUNCS.MIN = function(ctx, args, evalNode)
  local list, e = numList(ctx, args, evalNode)
  if not list then return e end
  if #list == 0 then return 0 end
  local m = list[1]
  for _, v in ipairs(list) do if v < m then m = v end end
  return m
end
FUNCS.MAX = function(ctx, args, evalNode)
  local list, e = numList(ctx, args, evalNode)
  if not list then return e end
  if #list == 0 then return 0 end
  local m = list[1]
  for _, v in ipairs(list) do if v > m then m = v end end
  return m
end
FUNCS.COUNT = function(ctx, args, evalNode)
  local list, e = numList(ctx, args, evalNode)
  if not list then return e end
  return #list
end

-- Single-argument math helpers.
local function fn1(name, f)
  FUNCS[name] = function(ctx, args, evalNode)
    if #args ~= 1 then return err(S.E_VALUE) end
    local v = evalNode(args[1])
    if isErr(v) then return v end
    local n = toNum(v)
    if n == nil then return err(S.E_VALUE) end
    return f(n)
  end
end
fn1("ABS", math.abs)
fn1("SQRT", function(n) if n < 0 then return err(S.E_VALUE) end return math.sqrt(n) end)
fn1("FLOOR", math.floor)
fn1("CEIL", math.ceil)
FUNCS.CEILING = function(...) return FUNCS.CEIL(...) end
fn1("INT", function(n) return math.floor(n) end)

FUNCS.ROUND = function(ctx, args, evalNode)
  if #args < 1 or #args > 2 then return err(S.E_VALUE) end
  local v = evalNode(args[1])
  if isErr(v) then return v end
  local n = toNum(v)
  if n == nil then return err(S.E_VALUE) end
  local digits = 0
  if args[2] then
    local d = evalNode(args[2])
    if isErr(d) then return d end
    digits = toNum(d) or 0
  end
  local mult = 10 ^ digits
  -- Round HALF AWAY FROM ZERO, which is what a spreadsheet user expects
  -- (Lua's %.0f would round half to even: 2.5 -> 2).
  local x = n * mult
  local rounded = (x >= 0) and math.floor(x + 0.5) or math.ceil(x - 0.5)
  return rounded / mult
end

FUNCS.POWER = function(ctx, args, evalNode)
  if #args ~= 2 then return err(S.E_VALUE) end
  local a, b = evalNode(args[1]), evalNode(args[2])
  if isErr(a) then return a end
  if isErr(b) then return b end
  local x, y = toNum(a), toNum(b)
  if x == nil or y == nil then return err(S.E_VALUE) end
  return x ^ y
end

FUNCS.MOD = function(ctx, args, evalNode)
  if #args ~= 2 then return err(S.E_VALUE) end
  local a, b = evalNode(args[1]), evalNode(args[2])
  if isErr(a) then return a end
  if isErr(b) then return b end
  local x, y = toNum(a), toNum(b)
  if x == nil or y == nil then return err(S.E_VALUE) end
  if y == 0 then return err(S.E_DIV) end
  return x % y
end

FUNCS.IF = function(ctx, args, evalNode)
  if #args < 2 or #args > 3 then return err(S.E_VALUE) end
  local cond = evalNode(args[1])
  if isErr(cond) then return cond end
  local truthy
  if type(cond) == "boolean" then truthy = cond
  else
    local n = toNum(cond)
    truthy = (n ~= nil and n ~= 0)
  end
  if truthy then return evalNode(args[2]) end
  if args[3] then return evalNode(args[3]) end
  return 0
end

FUNCS.AND = function(ctx, args, evalNode)
  for _, a in ipairs(args) do
    local v = evalNode(a)
    if isErr(v) then return v end
    local n = toNum(v)
    if n == nil or n == 0 then return 0 end
  end
  return 1
end
FUNCS.OR = function(ctx, args, evalNode)
  for _, a in ipairs(args) do
    local v = evalNode(a)
    if isErr(v) then return v end
    local n = toNum(v)
    if n ~= nil and n ~= 0 then return 1 end
  end
  return 0
end
FUNCS.NOT = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local v = evalNode(args[1])
  if isErr(v) then return v end
  local n = toNum(v)
  return (n == nil or n == 0) and 1 or 0
end

-- Text functions.
FUNCS.LEN = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local v = evalNode(args[1])
  if isErr(v) then return v end
  return #toStr(v)
end
FUNCS.UPPER = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local v = evalNode(args[1])
  if isErr(v) then return v end
  return toStr(v):upper()
end
FUNCS.LOWER = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local v = evalNode(args[1])
  if isErr(v) then return v end
  return toStr(v):lower()
end
FUNCS.CONCAT = function(ctx, args, evalNode)
  local parts = {}
  for _, a in ipairs(args) do
    if a.k == "range" then
      for c = math.min(a.c1, a.c2), math.max(a.c1, a.c2) do
        for r = math.min(a.r1, a.r2), math.max(a.r1, a.r2) do
          local v = ctx.get(c, r)
          if isErr(v) then return v end
          parts[#parts + 1] = toStr(v)
        end
      end
    else
      local v = evalNode(a)
      if isErr(v) then return v end
      parts[#parts + 1] = toStr(v)
    end
  end
  return table.concat(parts)
end
S.FUNCS = FUNCS

--- Evaluate an AST against a context. ctx.get(c, r) returns a cell's
--- VALUE (number/string/err) and is responsible for recursion + cycle
--- detection. Pure given ctx.
function S.evalAst(ast, ctx, depth)
  depth = (depth or 0) + 1
  if depth > S.MAX_DEPTH then return err(S.E_DEPTH) end
  local function ev(node) return S.evalAst(node, ctx, depth) end

  local k = ast.k
  if k == "num" or k == "str" then return ast.v end
  if k == "err" then return err(ast.v) end
  if k == "ref" then return ctx.get(ast.c, ast.r) end
  if k == "range" then return err(S.E_VALUE) end   -- bare range isn't a value
  if k == "unary" then
    local v = ev(ast.a)
    if isErr(v) then return v end
    local n = toNum(v)
    if n == nil then return err(S.E_VALUE) end
    return (ast.op == "-") and -n or n
  end
  if k == "call" then
    local f = FUNCS[ast.name]
    if not f then return err(S.E_NAME) end
    return f(ctx, ast.args, ev)
  end
  if k == "bin" then
    local a, b = ev(ast.a), ev(ast.b)
    if isErr(a) then return a end
    if isErr(b) then return b end
    local op = ast.op
    -- "=" and "<>" compare TEXT when either side is non-numeric, so
    -- ="yes"="yes" behaves the way a user expects.
    if op == "=" or op == "<>" then
      local na, nb = toNum(a), toNum(b)
      local same
      if na ~= nil and nb ~= nil then same = (na == nb)
      else same = (toStr(a) == toStr(b)) end
      if op == "=" then return same and 1 or 0 end
      return same and 0 or 1
    end
    local na, nb = toNum(a), toNum(b)
    if na == nil or nb == nil then
      -- "+" over text is a common typo for CONCAT; be explicit instead
      -- of silently concatenating.
      return err(S.E_VALUE)
    end
    if op == "+" then return na + nb end
    if op == "-" then return na - nb end
    if op == "*" then return na * nb end
    if op == "/" then
      if nb == 0 then return err(S.E_DIV) end
      return na / nb
    end
    if op == "%" then
      if nb == 0 then return err(S.E_DIV) end
      return na % nb
    end
    if op == "^" then return na ^ nb end
    if op == "<" then return (na < nb) and 1 or 0 end
    if op == ">" then return (na > nb) and 1 or 0 end
    if op == "<=" then return (na <= nb) and 1 or 0 end
    if op == ">=" then return (na >= nb) and 1 or 0 end
    return err(S.E_SYNTAX)
  end
  return err(S.E_SYNTAX)
end

-- ============================================================
-- Sheet-level evaluation (memoized, cycle-safe)
-- ============================================================

--- Evaluate every referenced cell on demand. Returns a `values` table
--- keyed like the store, plus a get(c, r) accessor. A cell currently
--- being evaluated that is reached again is a CYCLE — reported as
--- #CYCLE! on every cell in the loop rather than hanging.
function S.evaluator(sh)
  local memo, visiting = {}, {}
  local ctx = {}
  function ctx.get(c, r)
    local k = key(c, r)
    if memo[k] ~= nil then
      local m = memo[k]
      if m == "\0nil" then return nil end
      return m
    end
    if visiting[k] then return err(S.E_CYCLE) end
    local rawTxt = sh.cells[k]
    if rawTxt == nil or rawTxt == "" then return nil end

    local value
    if rawTxt:sub(1, 1) == "=" then
      visiting[k] = true
      local ast, perr = S.parse(rawTxt:sub(2))
      if not ast then
        value = err(perr or S.E_SYNTAX)
      else
        value = S.evalAst(ast, ctx, 0)
      end
      visiting[k] = nil
    else
      local n = tonumber(rawTxt)
      value = n or rawTxt
    end
    memo[k] = (value == nil) and "\0nil" or value
    return value
  end
  ctx.values = memo
  return ctx
end

--- The DISPLAY string for a cell, given an evaluator. Numbers are
--- trimmed to `places` decimals when they don't land on an integer.
function S.display(sh, ctx, c, r, places)
  local v = ctx.get(c, r)
  if v == nil then return "" end
  if isErr(v) then return v.e end
  if type(v) == "number" then
    if v ~= v then return "#NAN!" end                        -- 0/0 style
    if v == math.huge or v == -math.huge then return "#INF!" end
    if v == math.floor(v) and math.abs(v) < 1e15 then
      return string.format("%d", v)
    end
    return string.format("%." .. (places or 4) .. "g", v)
  end
  return tostring(v)
end

-- ============================================================
-- Serialization (a small, hand-parsed text format)
-- ============================================================
-- One cell per line: "A1<TAB>raw text". Chosen over kernel.serialize so
-- a .calc file is greppable/diffable, survives hand-editing, and — most
-- importantly — LOADING IS NOT EXECUTION: the loader only ever assigns
-- strings into cells. Tabs and newlines are escaped so a cell's text can
-- never forge a new record.

local function escape(s)
  return (s:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n"):gsub("\r", ""))
end
local function unescape(s)
  local out, i = {}, 1
  while i <= #s do
    local ch = s:sub(i, i)
    if ch == "\\" then
      local nx = s:sub(i + 1, i + 1)
      if nx == "t" then out[#out + 1] = "\t"; i = i + 2
      elseif nx == "n" then out[#out + 1] = "\n"; i = i + 2
      elseif nx == "\\" then out[#out + 1] = "\\"; i = i + 2
      else out[#out + 1] = ch; i = i + 1 end
    else
      out[#out + 1] = ch; i = i + 1
    end
  end
  return table.concat(out)
end

function S.serialize(sh)
  local lines = { "TOSCALC1" }
  -- Deterministic order (column-major by row) so saves diff cleanly.
  local keys = {}
  for k in pairs(sh.cells) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ac, ar = a:match("^(%d+):(%d+)$")
    local bc, br = b:match("^(%d+):(%d+)$")
    ac, ar, bc, br = tonumber(ac), tonumber(ar), tonumber(bc), tonumber(br)
    if ar ~= br then return ar < br end
    return ac < bc
  end)
  for _, k in ipairs(keys) do
    local c, r = k:match("^(%d+):(%d+)$")
    lines[#lines + 1] = S.refName(tonumber(c), tonumber(r))
      .. "\t" .. escape(sh.cells[k])
  end
  return table.concat(lines, "\n")
end

--- Parse a saved sheet. Unknown/garbled lines are SKIPPED rather than
--- aborting the load: a partially-corrupt file should still open with
--- everything that survived, not refuse to open at all.
function S.deserialize(text)
  local sh = S.new()
  if type(text) ~= "string" then return sh end
  local first = true
  local skipped = 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if first then
      first = false
      if line ~= "TOSCALC1" then
        -- No/av unknown header: try to read it anyway (hand-made file).
        local ref, val = line:match("^(%a+%d+)\t(.*)$")
        if ref then
          local c, r = S.parseRef(ref)
          if c then S.set(sh, c, r, unescape(val)) end
        end
      end
    elseif line ~= "" then
      local ref, val = line:match("^(%a+%d+)\t(.*)$")
      -- Same truncation trap as the tokenizer's range branch: keep the
      -- call out of an `and` so the ROW survives.
      local c, r
      if ref then c, r = S.parseRef(ref) end
      if c then S.set(sh, c, r, unescape(val)) else skipped = skipped + 1 end
    end
  end
  sh.skipped = skipped
  return sh
end

-- ============================================================
-- CSV export (a spreadsheet people can take elsewhere)
-- ============================================================

function S.toCSV(sh, ctx)
  local rows = {}
  for r = 1, sh.rows do
    local cols = {}
    for c = 1, sh.cols do
      local v = S.display(sh, ctx, c, r)
      -- Quote when the value contains a comma, quote or newline.
      if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
      cols[#cols + 1] = v
    end
    -- Trim trailing empties so a sparse sheet doesn't export a rectangle
    -- of commas.
    while #cols > 0 and cols[#cols] == "" do cols[#cols] = nil end
    rows[#rows + 1] = table.concat(cols, ",")
  end
  while #rows > 0 and rows[#rows] == "" do rows[#rows] = nil end
  return table.concat(rows, "\n")
end

return S
