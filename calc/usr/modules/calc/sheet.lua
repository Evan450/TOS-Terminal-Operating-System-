

































local S = {}

S.MAX_COLS = 26 * 3      
S.MAX_ROWS = 512
S.MAX_DEPTH = 32         
S.DEFAULT_WIDTH = 9      
S.MIN_WIDTH, S.MAX_WIDTH = 1, 60





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
S.E_NA    = "#N/A"
S.E_ERR   = "#ERR!"






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



function S.parseRef(s)
  if type(s) ~= "string" then return nil end
  local d1, col, d2, row = s:match("^(%$?)(%a+)(%$?)(%d+)$")
  if not col then return nil end
  local c = S.colIndex(col)
  local r = tonumber(row)
  if not c or not r or r < 1 then return nil end
  if c > S.MAX_COLS or r > S.MAX_ROWS then return nil end
  return c, r, d1 == "$", d2 == "$"
end

function S.refName(c, r, absC, absR)
  return (absC and "$" or "") .. S.colName(c) .. (absR and "$" or "") .. tostring(r)
end



function S.parseRange(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("%s", "")
  local a, b = s:match("^([%$%w]+)%.%.([%$%w]+)$")
  if not a then a, b = s:match("^([%$%w]+)[:%.]([%$%w]+)$") end
  if not a then a, b = s, s end
  local c1, r1 = S.parseRef(a)
  local c2, r2 = S.parseRef(b)
  if not c1 or not c2 then return nil end
  return math.min(c1, c2), math.min(r1, r2), math.max(c1, c2), math.max(r1, r2)
end

function S.rangeName(c1, r1, c2, r2)
  local a = S.refName(c1, r1)
  if c1 == c2 and r1 == r2 then return a .. ".." .. a end
  return a .. ".." .. S.refName(c2, r2)
end



local function key(c, r) return c .. ":" .. r end
S._key = key
function S.unkey(k)
  local c, r = k:match("^(%d+):(%d+)$")
  return tonumber(c), tonumber(r)
end





function S.new()
  return {
    cells = {},          
    fmt   = {},          
    colw  = {},          
    names = {},          
    gfmt  = "G",         
    gwidth = S.DEFAULT_WIDTH,
    gprefix = "'",       
    recalc = "auto",     
    graph = {},          
    print = {},          
    sort  = {},          
    cols  = 8,           
    rows  = 20,
  }
end


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


function S.raw(sh, c, r) return sh.cells[key(c, r)] or "" end

function S.width(sh, c) return sh.colw[c] or sh.gwidth or S.DEFAULT_WIDTH end
function S.cellFmt(sh, c, r) return sh.fmt[key(c, r)] or sh.gfmt or "G" end






local PREFIX_ALIGN = { ["'"] = "L", ['"'] = "R", ["^"] = "C", ["\\"] = "REP" }
S.PREFIX_ALIGN = PREFIX_ALIGN






function S.classify(raw)
  if raw == nil or raw == "" then return "empty" end
  local first = raw:sub(1, 1)
  local align = PREFIX_ALIGN[first]
  if align then return "label", raw:sub(2), align end
  if first == "=" then return "formula", raw:sub(2) end
  
  
  local n = tonumber(raw)
  if n and raw:find("^[%d%.%-%+]") then return "number", n end
  if first == "+" or first == "@" or first == "(" or first == "-" or first == "#"
     or first == "." or first:find("%d") or first == "$" then
    return "formula", raw
  end
  return "label", raw, nil
end







local OPS2 = { ["<="] = true, [">="] = true, ["<>"] = true }
local OPS1 = { ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true,
               ["%"] = true, ["^"] = true, ["="] = true, ["<"] = true,
               [">"] = true, ["&"] = true }
local WORD_OPS = { ["#AND#"] = true, ["#OR#"] = true, ["#NOT#"] = true }



local function refAt(src, i)
  local word = src:match("^%$?%a+%$?%d+", i)
  if not word then return nil end
  
  local after = src:sub(i + #word, i + #word)
  if after:match("[%w_]") then return nil end
  if not S.parseRef(word) then return nil end
  return word
end

function S.tokenize(src)
  local toks, i, n = {}, 1, #src
  while i <= n do
    local ch = src:sub(i, i)
    if ch == " " or ch == "\t" then
      i = i + 1
    elseif ch == '"' then
      
      
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
      if j > n then return nil, S.E_SYNTAX end      
      toks[#toks + 1] = { t = "str", v = table.concat(buf) }
      i = j + 1
    elseif ch:match("%d") or (ch == "." and src:sub(i + 1, i + 1):match("%d")) then
      local numStr = src:match("^%d*%.?%d+", i) or src:match("^%d+", i)
      
      local expPart = src:match("^[eE][%+%-]?%d+", i + #numStr)
      if expPart then numStr = numStr .. expPart end
      toks[#toks + 1] = { t = "num", v = tonumber(numStr) }
      i = i + #numStr
    elseif ch == "#" then
      local w = src:match("^#%a+#", i)
      if w and WORD_OPS[w:upper()] then
        toks[#toks + 1] = { t = "op", v = w:upper() }; i = i + #w
      elseif src:sub(i, i + 4):upper() == "#REF!" then
        
        toks[#toks + 1] = { t = "err", v = S.E_REF }; i = i + 5
      else
        return nil, S.E_SYNTAX
      end
    elseif ch == "$" or ch:match("%a") then
      local word = refAt(src, i)
      if word then
        local after = i + #word
        
        local sepLen = 0
        if src:sub(after, after + 1) == ".." then sepLen = 2
        elseif src:sub(after, after) == ":" or src:sub(after, after) == "." then sepLen = 1 end
        local word2 = sepLen > 0 and refAt(src, after + sepLen) or nil
        if word2 then
          local c1, r1, a1, b1 = S.parseRef(word)
          local c2, r2, a2, b2 = S.parseRef(word2)
          toks[#toks + 1] = { t = "range", c1 = c1, r1 = r1, c2 = c2, r2 = r2 }
          i = after + sepLen + #word2
        elseif sepLen == 1 and src:sub(after, after) == ":" then
          return nil, S.E_REF            
        else
          local c, r = S.parseRef(word)
          toks[#toks + 1] = { t = "ref", c = c, r = r }
          i = after
        end
      elseif ch == "$" then
        return nil, S.E_SYNTAX
      else
        local word2 = src:match("^%a[%w_]*", i)
        toks[#toks + 1] = { t = "name", v = word2:upper() }
        i = i + #word2
      end
    elseif ch == "@" then
      
      local word = src:match("^@(%a[%w_]*)", i)
      if not word then return nil, S.E_SYNTAX end
      toks[#toks + 1] = { t = "name", v = word:upper(), at = true }
      i = i + 1 + #word
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

local parseExpr   

local function parsePrimary(p)
  local t = p:next()
  if not t then return nil, S.E_SYNTAX end
  if t.t == "num" then return { k = "num", v = t.v } end
  if t.t == "str" then return { k = "str", v = t.v } end
  if t.t == "err" then return { k = "err", v = t.v } end
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
    
    if t.at then return { k = "call", name = t.v, args = {} } end
    
    
    if t.v == "TRUE" then return { k = "num", v = 1 } end
    if t.v == "FALSE" then return { k = "num", v = 0 } end
    return { k = "name", v = t.v }
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
    local rhs, e2 = parsePower(p)          
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
local LOGOPS = { ["#AND#"] = true, ["#OR#"] = true, ["&"] = true }

local function parseMul(p) return parseBinLevel(p, MULOPS, parseUnary) end
local function parseAdd(p) return parseBinLevel(p, ADDOPS, parseMul) end
local function parseCmp(p) return parseBinLevel(p, CMPOPS, parseAdd) end
local function parseNot(p)
  local t = p:peek()
  if t and t.t == "op" and t.v == "#NOT#" then
    p:next()
    local a, e = parseNot(p)
    if not a then return nil, e end
    return { k = "not", a = a }
  end
  return parseCmp(p)
end
parseExpr = function(p) return parseBinLevel(p, LOGOPS, parseNot) end


function S.parse(src)
  local toks, terr = S.tokenize(src)
  if not toks then return nil, terr end
  if #toks == 0 then return nil, S.E_SYNTAX end
  local p = parser(toks)
  local ast, e = parseExpr(p)
  if not ast then return nil, e end
  if p:peek() then return nil, S.E_SYNTAX end     
  return ast
end





local function toNum(v)
  if type(v) == "number" then return v end
  if type(v) == "boolean" then return v and 1 or 0 end
  if type(v) == "string" then
    if v == "" then return 0 end
    return tonumber(v)                            
  end
  if v == nil then return 0 end                   
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



local function rangeOf(node, ctx)
  if node.k == "range" then
    return math.min(node.c1, node.c2), math.min(node.r1, node.r2),
           math.max(node.c1, node.c2), math.max(node.r1, node.r2)
  end
  if node.k == "name" and ctx.names then
    local rg = ctx.names[node.v]
    if rg then return rg[1], rg[2], rg[3], rg[4] end
  end
  return nil
end
S.rangeOf = rangeOf



local function numList(ctx, args, evalNode)
  local out = {}
  for _, a in ipairs(args) do
    local c1, r1, c2, r2 = rangeOf(a, ctx)
    if c1 then
      for c = c1, c2 do
        for r = r1, r2 do
          local v = ctx.get(c, r)
          if isErr(v) then return nil, v end
          local n = toNum(v)
          
          
          if n ~= nil and not (v == nil or v == "") and type(v) ~= "string" then out[#out + 1] = n end
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

local function variance(ctx, args, evalNode)
  local list, e = numList(ctx, args, evalNode)
  if not list then return nil, e end
  if #list == 0 then return nil, err(S.E_DIV) end
  local s = 0
  for _, v in ipairs(list) do s = s + v end
  local mean = s / #list
  local q = 0
  for _, v in ipairs(list) do q = q + (v - mean) ^ 2 end
  return q / #list
end
FUNCS.VAR = function(ctx, args, evalNode)
  local v, e = variance(ctx, args, evalNode)
  return v or e
end
FUNCS.STD = function(ctx, args, evalNode)
  local v, e = variance(ctx, args, evalNode)
  return v and math.sqrt(v) or e
end


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
fn1("EXP", math.exp)
fn1("LN", function(n) if n <= 0 then return err(S.E_VALUE) end return math.log(n) end)
fn1("LOG", function(n) if n <= 0 then return err(S.E_VALUE) end return math.log(n, 10) end)
fn1("SIN", math.sin)
fn1("COS", math.cos)
fn1("TAN", math.tan)
fn1("ASIN", function(n) if n < -1 or n > 1 then return err(S.E_VALUE) end return math.asin(n) end)
fn1("ACOS", function(n) if n < -1 or n > 1 then return err(S.E_VALUE) end return math.acos(n) end)
fn1("ATAN", math.atan)

local function nums(ctx, args, evalNode, count)
  if #args ~= count then return nil, err(S.E_VALUE) end
  local out = {}
  for i = 1, count do
    local v = evalNode(args[i])
    if isErr(v) then return nil, v end
    local n = toNum(v)
    if n == nil then return nil, err(S.E_VALUE) end
    out[i] = n
  end
  return out
end

FUNCS.PI = function(ctx, args) if #args ~= 0 then return err(S.E_VALUE) end return math.pi end
FUNCS.ATAN2 = function(ctx, args, evalNode)
  local n, e = nums(ctx, args, evalNode, 2)
  if not n then return e end
  if n[1] == 0 and n[2] == 0 then return err(S.E_DIV) end
  return math.atan(n[2], n[1])           
end

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
  
  
  local x = n * mult
  local rounded = (x >= 0) and math.floor(x + 0.5) or math.ceil(x - 0.5)
  return rounded / mult
end

FUNCS.POWER = function(ctx, args, evalNode)
  local n, e = nums(ctx, args, evalNode, 2)
  if not n then return e end
  return n[1] ^ n[2]
end

FUNCS.MOD = function(ctx, args, evalNode)
  local n, e = nums(ctx, args, evalNode, 2)
  if not n then return e end
  if n[2] == 0 then return err(S.E_DIV) end
  return n[1] % n[2]
end



FUNCS.PMT = function(ctx, args, evalNode)
  local n, e = nums(ctx, args, evalNode, 3)
  if not n then return e end
  local pv, i, t = n[1], n[2], n[3]
  if t <= 0 then return err(S.E_VALUE) end
  if i == 0 then return pv / t end
  return pv * i / (1 - (1 + i) ^ -t)
end
FUNCS.PV = function(ctx, args, evalNode)
  local n, e = nums(ctx, args, evalNode, 3)
  if not n then return e end
  local pmt, i, t = n[1], n[2], n[3]
  if i == 0 then return pmt * t end
  return pmt * (1 - (1 + i) ^ -t) / i
end
FUNCS.FV = function(ctx, args, evalNode)
  local n, e = nums(ctx, args, evalNode, 3)
  if not n then return e end
  local pmt, i, t = n[1], n[2], n[3]
  if i == 0 then return pmt * t end
  return pmt * ((1 + i) ^ t - 1) / i
end
FUNCS.NPV = function(ctx, args, evalNode)
  if #args < 2 then return err(S.E_VALUE) end
  local rate = toNum(evalNode(args[1]))
  if rate == nil then return err(S.E_VALUE) end
  local rest = {}
  for i = 2, #args do rest[#rest + 1] = args[i] end
  local list, e = numList(ctx, rest, evalNode)
  if not list then return e end
  local s = 0
  for k, v in ipairs(list) do s = s + v / (1 + rate) ^ k end
  return s
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
FUNCS.TRUE = function(ctx, args) if #args ~= 0 then return err(S.E_VALUE) end return 1 end
FUNCS.FALSE = function(ctx, args) if #args ~= 0 then return err(S.E_VALUE) end return 0 end
FUNCS.NA = function(ctx, args) return err(S.E_NA) end
FUNCS.ERR = function(ctx, args) return err(S.E_ERR) end


local function isTest(name, pred)
  FUNCS[name] = function(ctx, args, evalNode)
    if #args ~= 1 then return err(S.E_VALUE) end
    return pred(evalNode(args[1])) and 1 or 0
  end
end
isTest("ISERR", function(v) return isErr(v) end)
isTest("ISNA", function(v) return isErr(v) and v.e == S.E_NA end)
isTest("ISNUMBER", function(v) return type(v) == "number" or v == nil end)
isTest("ISSTRING", function(v) return type(v) == "string" end)


FUNCS.CHOOSE = function(ctx, args, evalNode)
  if #args < 2 then return err(S.E_VALUE) end
  local i = toNum(evalNode(args[1]))
  if i == nil then return err(S.E_VALUE) end
  i = math.floor(i)
  if i < 0 or i > #args - 2 then return err(S.E_VALUE) end
  return evalNode(args[i + 2])
end




local function lookup(vertical)
  return function(ctx, args, evalNode)
    if #args ~= 3 then return err(S.E_VALUE) end
    local x = evalNode(args[1])
    if isErr(x) then return x end
    local c1, r1, c2, r2 = rangeOf(args[2], ctx)
    if not c1 then return err(S.E_VALUE) end
    local off = toNum(evalNode(args[3]))
    if off == nil then return err(S.E_VALUE) end
    off = math.floor(off)
    local count = vertical and (r2 - r1 + 1) or (c2 - c1 + 1)
    local span = vertical and (c2 - c1) or (r2 - r1)
    if off < 0 or off > span then return err(S.E_REF) end
    local hit
    for i = 0, count - 1 do
      local kc, kr = vertical and c1 or (c1 + i), vertical and (r1 + i) or r1
      local k = ctx.get(kc, kr)
      if type(x) == "string" then
        if type(k) == "string" and k:lower() == x:lower() then hit = i; break end
      else
        local nk = type(k) == "number" and k or nil
        if nk ~= nil then
          if nk <= toNum(x) then hit = i else break end
        end
      end
    end
    if not hit then return err(S.E_NA) end
    if vertical then return ctx.get(c1 + off, r1 + hit) end
    return ctx.get(c1 + hit, r1 + off)
  end
end
FUNCS.VLOOKUP = lookup(true)
FUNCS.HLOOKUP = lookup(false)


local function str1(ctx, args, evalNode, i)
  local v = evalNode(args[i])
  if isErr(v) then return nil, v end
  return toStr(v)
end
local function num1(ctx, args, evalNode, i)
  local v = evalNode(args[i])
  if isErr(v) then return nil, v end
  local n = toNum(v)
  if n == nil then return nil, err(S.E_VALUE) end
  return n
end
FUNCS.LEN = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1)
  return s and #s or e
end
FUNCS.LENGTH = function(...) return FUNCS.LEN(...) end
FUNCS.UPPER = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1)
  return s and s:upper() or e
end
FUNCS.LOWER = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1)
  return s and s:lower() or e
end
FUNCS.PROPER = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1)
  if not s then return e end
  return (s:lower():gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end))
end
FUNCS.TRIM = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1)
  if not s then return e end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end
FUNCS.LEFT = function(ctx, args, evalNode)
  if #args ~= 2 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1); if not s then return e end
  local n, e2 = num1(ctx, args, evalNode, 2); if not n then return e2 end
  if n < 0 then return err(S.E_VALUE) end
  return s:sub(1, math.floor(n))
end
FUNCS.RIGHT = function(ctx, args, evalNode)
  if #args ~= 2 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1); if not s then return e end
  local n, e2 = num1(ctx, args, evalNode, 2); if not n then return e2 end
  if n < 0 then return err(S.E_VALUE) end
  n = math.floor(n)
  if n == 0 then return "" end
  return s:sub(-n)
end
FUNCS.MID = function(ctx, args, evalNode)
  if #args ~= 3 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1); if not s then return e end
  local st, e2 = num1(ctx, args, evalNode, 2); if not st then return e2 end
  local n, e3 = num1(ctx, args, evalNode, 3); if not n then return e3 end
  if st < 0 or n < 0 then return err(S.E_VALUE) end
  st = math.floor(st)
  return s:sub(st + 1, st + math.floor(n))
end
FUNCS.FIND = function(ctx, args, evalNode)
  if #args < 2 or #args > 3 then return err(S.E_VALUE) end
  local needle, e = str1(ctx, args, evalNode, 1); if not needle then return e end
  local hay, e2 = str1(ctx, args, evalNode, 2); if not hay then return e2 end
  local st = 0
  if args[3] then
    local n, e3 = num1(ctx, args, evalNode, 3); if not n then return e3 end
    st = math.floor(n)
  end
  local at = hay:find(needle, st + 1, true)
  if not at then return err(S.E_VALUE) end
  return at - 1
end
FUNCS.EXACT = function(ctx, args, evalNode)
  if #args ~= 2 then return err(S.E_VALUE) end
  local a, e = str1(ctx, args, evalNode, 1); if not a then return e end
  local b, e2 = str1(ctx, args, evalNode, 2); if not b then return e2 end
  return a == b and 1 or 0
end
FUNCS.REPEAT = function(ctx, args, evalNode)
  if #args ~= 2 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1); if not s then return e end
  local n, e2 = num1(ctx, args, evalNode, 2); if not n then return e2 end
  if n < 0 or #s * n > 512 then return err(S.E_VALUE) end
  return s:rep(math.floor(n))
end
FUNCS.STRING = function(ctx, args, evalNode)
  if #args ~= 2 then return err(S.E_VALUE) end
  local x, e = num1(ctx, args, evalNode, 1); if not x then return e end
  local d, e2 = num1(ctx, args, evalNode, 2); if not d then return e2 end
  d = math.max(0, math.min(15, math.floor(d)))
  return string.format("%." .. d .. "f", x)
end
FUNCS.VALUE = function(ctx, args, evalNode)
  if #args ~= 1 then return err(S.E_VALUE) end
  local s, e = str1(ctx, args, evalNode, 1); if not s then return e end
  local n = tonumber((s:gsub("^%s+", ""):gsub("%s+$", "")))
  if n == nil then return err(S.E_VALUE) end
  return n
end
FUNCS.CONCAT = function(ctx, args, evalNode)
  local parts = {}
  for _, a in ipairs(args) do
    local c1, r1, c2, r2 = rangeOf(a, ctx)
    if c1 then
      for c = c1, c2 do
        for r = r1, r2 do
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




function S.evalAst(ast, ctx, depth)
  depth = (depth or 0) + 1
  if depth > S.MAX_DEPTH then return err(S.E_DEPTH) end
  local function ev(node) return S.evalAst(node, ctx, depth) end

  local k = ast.k
  if k == "num" or k == "str" then return ast.v end
  if k == "err" then return err(ast.v) end
  if k == "ref" then return ctx.get(ast.c, ast.r) end
  if k == "range" then return err(S.E_VALUE) end   
  if k == "name" then
    local c1, r1, c2, r2 = rangeOf(ast, ctx)
    if not c1 then return err(S.E_NAME) end
    if c1 == c2 and r1 == r2 then return ctx.get(c1, r1) end
    return err(S.E_VALUE)
  end
  if k == "unary" then
    local v = ev(ast.a)
    if isErr(v) then return v end
    
    
    if ast.op == "+" and type(v) == "string" then return v end
    local n = toNum(v)
    if n == nil then return err(S.E_VALUE) end
    return (ast.op == "-") and -n or n
  end
  if k == "not" then
    local v = ev(ast.a)
    if isErr(v) then return v end
    local n = toNum(v)
    return (n == nil or n == 0) and 1 or 0
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
    if op == "&" then return toStr(a) .. toStr(b) end
    
    
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
      
      
      return err(S.E_VALUE)
    end
    if op == "#AND#" then return (na ~= 0 and nb ~= 0) and 1 or 0 end
    if op == "#OR#" then return (na ~= 0 or nb ~= 0) and 1 or 0 end
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









function S.evaluator(sh)
  local memo, visiting = {}, {}
  local ctx = { names = sh.names }
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
    local kind, body = S.classify(rawTxt)
    if kind == "formula" then
      visiting[k] = true
      local ast, perr = S.parse(body)
      if not ast then
        value = err(perr or S.E_SYNTAX)
      else
        value = S.evalAst(ast, ctx, 0)
      end
      visiting[k] = nil
    elseif kind == "number" then
      value = body
    else
      value = body
    end
    memo[k] = (value == nil) and "\0nil" or value
    return value
  end
  ctx.values = memo
  return ctx
end








function S.display(sh, ctx, c, r, places)
  local v = ctx.get(c, r)
  if v == nil then return "" end
  if isErr(v) then return v.e end
  if type(v) == "number" then
    if v ~= v then return "#NAN!" end                        
    if v == math.huge or v == -math.huge then return "#INF!" end
    if v == math.floor(v) and math.abs(v) < 1e15 then
      return string.format("%d", v)
    end
    return string.format("%." .. (places or 4) .. "g", v)
  end
  return tostring(v)
end







S.FORMATS = { G = "General", F = "Fixed", S = "Scientific", C = "Currency",
              [","] = "Comma", P = "Percent", ["+"] = "+/-", T = "Text", H = "Hidden" }

local function commas(intStr)
  local neg = intStr:sub(1, 1) == "-"
  if neg then intStr = intStr:sub(2) end
  local out = intStr:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return (neg and "-" or "") .. out
end






local function fixed(v, places)
  local m = 10 ^ places
  local x = math.abs(v) * m
  local rounded = math.floor(x + 0.5) / m
  if v < 0 then rounded = -rounded end
  return string.format("%." .. places .. "f", rounded)
end

function S.formatNumber(v, code, width)
  code = code or "G"
  local kind, places = code:sub(1, 1), tonumber(code:sub(2)) or 2
  local s
  if v ~= v then s = "#NAN!"
  elseif v == math.huge or v == -math.huge then s = "#INF!"
  elseif kind == "F" then s = fixed(v, places)
  elseif kind == "S" then s = string.format("%." .. places .. "E", v)
  elseif kind == "C" or kind == "," then
    local int, frac = fixed(math.abs(v), places):match("^(%d+)(.*)$")
    s = commas(int) .. frac
    if kind == "C" then s = "$" .. s end
    if v < 0 then s = "(" .. s .. ")" end      
  elseif kind == "P" then s = fixed(v * 100, places) .. "%"
  elseif kind == "+" then
    local n = math.floor(math.abs(v))
    if n == 0 then s = "." else s = string.rep(v < 0 and "-" or "+", n) end
  else
    
    if v == math.floor(v) and math.abs(v) < 1e15 then s = string.format("%d", v)
    else s = string.format("%.10g", v) end
    if width and #s > width then
      for p = 9, 1, -1 do
        local t = string.format("%." .. p .. "g", v)
        if #t <= width then s = t; break end
        s = t
      end
    end
  end
  if width and #s > width then return string.rep("*", width), true end
  return s
end



function S.cellText(sh, ctx, c, r, width)
  width = width or S.width(sh, c)
  local raw = sh.cells[key(c, r)]
  if raw == nil or raw == "" then return "", "L" end
  local code = S.cellFmt(sh, c, r)
  if code == "H" then return "", "L" end
  local kind, body, align = S.classify(raw)
  if kind == "label" then
    if align == "REP" then
      if body == "" then return "", "L" end
      local s = body:rep(math.ceil(width / #body) + 1)
      return s:sub(1, width), "L"
    end
    align = align or PREFIX_ALIGN[sh.gprefix or "'"] or "L"
    return body, align
  end
  if code == "T" and kind == "formula" then return raw, "L" end
  local v = ctx.get(c, r)
  if v == nil then return "", "L" end
  if isErr(v) then return v.e, "R" end
  if type(v) == "number" then return (S.formatNumber(v, code, width)), "R" end
  return tostring(v), "L"
end















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

local function sortedKeys(t, cmp)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, cmp)
  return keys
end
local function byRowThenCol(a, b)
  local ac, ar = S.unkey(a)
  local bc, br = S.unkey(b)
  if ar ~= br then return ar < br end
  return ac < bc
end

S.GRAPH_KEYS = { "type", "x", "a", "b", "c", "title1", "title2" }



local function isRange(v) return S.parseRange(v) ~= nil end
local function isRef(v) return S.parseRef(v) ~= nil end
local function isText(v) return #v <= 120 end
S.SETTINGS = {
  print = { range = isRange, header = isText, footer = isText,
            formulas = function(v) return v == "1" or v == "0" end },
  sort  = { range = isRange, k1 = isRef, k2 = isRef,
            o1 = function(v) return v == "A" or v == "D" end,
            o2 = function(v) return v == "A" or v == "D" end },
}

function S.serialize(sh)
  local lines = { "TOSCALC2" }
  
  for _, k in ipairs(sortedKeys(sh.cells, byRowThenCol)) do
    local c, r = S.unkey(k)
    lines[#lines + 1] = S.refName(c, r) .. "\t" .. escape(sh.cells[k])
  end
  if (sh.gfmt or "G") ~= "G" then lines[#lines + 1] = "#gfmt " .. sh.gfmt end
  if (sh.gwidth or S.DEFAULT_WIDTH) ~= S.DEFAULT_WIDTH then lines[#lines + 1] = "#gwidth " .. sh.gwidth end
  if (sh.gprefix or "'") ~= "'" then lines[#lines + 1] = "#prefix " .. sh.gprefix end
  if sh.recalc == "manual" then lines[#lines + 1] = "#recalc manual" end
  for _, c in ipairs(sortedKeys(sh.colw)) do
    lines[#lines + 1] = "#width " .. S.colName(c) .. " " .. sh.colw[c]
  end
  for _, k in ipairs(sortedKeys(sh.fmt, byRowThenCol)) do
    local c, r = S.unkey(k)
    lines[#lines + 1] = "#fmt " .. S.refName(c, r) .. " " .. sh.fmt[k]
  end
  for _, name in ipairs(sortedKeys(sh.names)) do
    local rg = sh.names[name]
    lines[#lines + 1] = "#name " .. name .. " " .. S.rangeName(rg[1], rg[2], rg[3], rg[4])
  end
  for _, gk in ipairs(S.GRAPH_KEYS) do
    local v = sh.graph and sh.graph[gk]
    if v ~= nil and v ~= "" then lines[#lines + 1] = "#graph " .. gk .. " " .. escape(tostring(v)) end
  end
  for _, group in ipairs({ "print", "sort" }) do
    local t = sh[group] or {}
    for _, k in ipairs(sortedKeys(S.SETTINGS[group])) do
      local v = t[k]
      if v ~= nil and v ~= "" and v ~= false then
        if v == true then v = "1" end
        lines[#lines + 1] = "#" .. group .. " " .. k .. " " .. escape(tostring(v))
      end
    end
  end
  return table.concat(lines, "\n")
end




local function migrateV1(raw)
  local kind = S.classify(raw)
  if kind == "formula" and raw:sub(1, 1) ~= "=" then return "'" .. raw end
  return raw
end

local function validFmt(code)
  if type(code) ~= "string" then return false end
  local kind, n = code:sub(1, 1), code:sub(2)
  if kind == "G" or kind == "+" or kind == "T" or kind == "H" then return n == "" end
  if kind == "F" or kind == "S" or kind == "C" or kind == "," or kind == "P" then
    local d = tonumber(n)
    return d ~= nil and d >= 0 and d <= 15 and d == math.floor(d)
  end
  return false
end
S.validFmt = validFmt




function S.deserialize(text)
  local sh = S.new()
  if type(text) ~= "string" then return sh end
  local first = true
  local skipped = 0
  local v1 = true
  local function setCell(line)
    local ref, val = line:match("^(%$?%a+%$?%d+)\t(.*)$")
    
    
    local c, r
    if ref then c, r = S.parseRef(ref) end
    if not c then return false end
    local raw = unescape(val)
    if v1 then raw = migrateV1(raw) end
    S.set(sh, c, r, raw)
    return true
  end
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if first then
      first = false
      if line == "TOSCALC2" then v1 = false
      elseif line ~= "TOSCALC1" then
        
        setCell(line)
      end
    elseif line:sub(1, 1) == "#" and not v1 then
      local what, a, b = line:match("^#(%a+) (%S+) ?(.*)$")
      local ok = false
      if what == "gfmt" and validFmt(a) then sh.gfmt = a; ok = true
      elseif what == "gwidth" and tonumber(a) then
        sh.gwidth = math.max(S.MIN_WIDTH, math.min(S.MAX_WIDTH, math.floor(tonumber(a)))); ok = true
      elseif what == "prefix" and PREFIX_ALIGN[a] and a ~= "\\" then sh.gprefix = a; ok = true
      elseif what == "recalc" and (a == "manual" or a == "auto") then sh.recalc = a; ok = true
      elseif what == "width" and S.colIndex(a) and tonumber(b) then
        local c = S.colIndex(a)
        if c <= S.MAX_COLS then
          sh.colw[c] = math.max(S.MIN_WIDTH, math.min(S.MAX_WIDTH, math.floor(tonumber(b)))); ok = true
        end
      elseif what == "fmt" and validFmt(b) then
        local c, r = S.parseRef(a)
        if c then sh.fmt[key(c, r)] = b; ok = true end
      elseif what == "name" and a:match("^%a[%w_]*$") and not S.parseRef(a) then
        local c1, r1, c2, r2 = S.parseRange(b)
        if c1 then sh.names[a:upper()] = { c1, r1, c2, r2 }; ok = true end
      elseif what == "graph" then
        for _, gk in ipairs(S.GRAPH_KEYS) do
          if gk == a then sh.graph[gk] = unescape(b); ok = true end
        end
      elseif (what == "print" or what == "sort") and S.SETTINGS[what][a] then
        local v = unescape(b)
        if S.SETTINGS[what][a](v) then
          if what == "print" and a == "formulas" then v = (v == "1") end
          sh[what][a] = v; ok = true
        end
      end
      if not ok then skipped = skipped + 1 end
    elseif line ~= "" then
      if not setCell(line) then skipped = skipped + 1 end
    end
  end
  sh.skipped = skipped
  return sh
end





function S.toCSV(sh, ctx)
  local rows = {}
  for r = 1, sh.rows do
    local cols = {}
    for c = 1, sh.cols do
      local v = S.display(sh, ctx, c, r)
      
      if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
      cols[#cols + 1] = v
    end
    
    
    while #cols > 0 and cols[#cols] == "" do cols[#cols] = nil end
    rows[#rows + 1] = table.concat(cols, ",")
  end
  while #rows > 0 and rows[#rows] == "" do rows[#rows] = nil end
  return table.concat(rows, "\n")
end





function S.fromCSV(sh, text, c0, r0)
  c0, r0 = c0 or 1, r0 or 1
  local n = 0
  local r = r0
  local i, len = 1, #text
  local row, field, inQuotes = {}, {}, false
  local function endField()
    row[#row + 1] = table.concat(field); field = {}
  end
  local function endRow()
    endField()
    for j, v in ipairs(row) do
      if v ~= "" then
        local kind = S.classify(v)
        if kind == "formula" or v:sub(1, 1) == "=" then v = "'" .. v end
        S.set(sh, c0 + j - 1, r, v); n = n + 1
      end
    end
    row = {}
    r = r + 1
  end
  while i <= len do
    local ch = text:sub(i, i)
    if inQuotes then
      if ch == '"' then
        if text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1
        else inQuotes = false end
      else field[#field + 1] = ch end
    elseif ch == '"' then inQuotes = true
    elseif ch == "," then endField()
    elseif ch == "\n" then endRow()
    elseif ch ~= "\r" then field[#field + 1] = ch end
    i = i + 1
  end
  if #field > 0 or #row > 0 then endRow() end
  return n
end

return S
