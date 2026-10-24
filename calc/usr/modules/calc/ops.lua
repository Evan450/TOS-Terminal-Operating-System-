
























local S = require("calc.sheet")
local O = {}

local key, unkey = S._key, S.unkey




local function refAt(src, i)
  local word = src:match("^%$?%a+%$?%d+", i)
  if not word then return nil end
  if src:sub(i + #word, i + #word):match("[%w_]") then return nil end
  if not S.parseRef(word) then return nil end
  return word
end






function O.rewrite(src, onRef, onRange)
  local out, i, n, changed = {}, 1, #src, false
  local function emit(s) out[#out + 1] = s end
  while i <= n do
    local ch = src:sub(i, i)
    if ch == '"' then
      local j = i + 1
      while j <= n do
        if src:sub(j, j) == '"' then
          if src:sub(j + 1, j + 1) == '"' then j = j + 2 else break end
        else j = j + 1 end
      end
      emit(src:sub(i, j)); i = j + 1
    elseif ch:match("%d") or (ch == "." and src:sub(i + 1, i + 1):match("%d")) then
      
      local num = src:match("^%d*%.?%d+", i) or src:match("^%d+", i)
      local ex = src:match("^[eE][%+%-]?%d+", i + #num)
      if ex then num = num .. ex end
      emit(num); i = i + #num
    elseif ch == "@" then
      local w = src:match("^@[%a_][%w_]*", i) or "@"
      emit(w); i = i + #w
    elseif ch == "#" then
      local w = src:match("^#%a+[#!]", i) or "#"
      emit(w); i = i + #w
    elseif ch == "$" or ch:match("%a") then
      local w1 = refAt(src, i)
      if not w1 then
        local w = src:match("^[%a_][%w_]*", i) or ch
        emit(w); i = i + #w
      else
        local after = i + #w1
        local sep = ""
        if src:sub(after, after + 1) == ".." then sep = ".."
        elseif src:sub(after, after) == ":" or src:sub(after, after) == "." then sep = src:sub(after, after) end
        local w2 = sep ~= "" and refAt(src, after + #sep) or nil
        local c1, r1, a1, b1 = S.parseRef(w1)
        if w2 then
          local c2, r2, a2, b2 = S.parseRef(w2)
          local n1, m1, n2, m2 = onRange(c1, r1, c2, r2, a1, b1, a2, b2)
          if n1 == nil then emit(S.E_REF); changed = true
          else
            local t = S.refName(n1, m1, a1, b1) .. sep .. S.refName(n2, m2, a2, b2)
            if t ~= w1 .. sep .. w2 then changed = true end
            emit(t)
          end
          i = after + #sep + #w2
        else
          local nc, nr = onRef(c1, r1, a1, b1)
          if nc == nil then emit(S.E_REF); changed = true
          else
            local t = S.refName(nc, nr, a1, b1)
            if t ~= w1 then changed = true end
            emit(t)
          end
          i = after
        end
      end
    else
      emit(ch); i = i + 1
    end
  end
  return table.concat(out), changed
end

local function onSheet(c, r)
  return c >= 1 and r >= 1 and c <= S.MAX_COLS and r <= S.MAX_ROWS
end



function O.shift(raw, dc, dr)
  local kind = S.classify(raw)
  if kind ~= "formula" then return raw end
  local function one(c, r, ac, ar)
    local nc = ac and c or c + dc
    local nr = ar and r or r + dr
    if not onSheet(nc, nr) then return nil end
    return nc, nr
  end
  return (O.rewrite(raw, one, function(c1, r1, c2, r2, a1, b1, a2, b2)
    local x1, y1 = one(c1, r1, a1, b1)
    local x2, y2 = one(c2, r2, a2, b2)
    if not x1 or not x2 then return nil end
    return x1, y1, x2, y2
  end))
end



local function rewriteSheet(sh, onRef, onRange)
  local n = 0
  for k, raw in pairs(sh.cells) do
    if S.classify(raw) == "formula" then
      local new, changed = O.rewrite(raw, onRef, onRange)
      if changed then sh.cells[k] = new; n = n + 1 end
    end
  end
  for name, rg in pairs(sh.names) do
    local c1, r1, c2, r2 = onRange(rg[1], rg[2], rg[3], rg[4])
    if c1 then sh.names[name] = { math.min(c1, c2), math.min(r1, r2), math.max(c1, c2), math.max(r1, r2) }
    else sh.names[name] = nil end
  end
  return n
end

local function blockCells(sh, c1, r1, c2, r2)
  local cells, fmts = {}, {}
  for c = c1, c2 do
    for r = r1, r2 do
      local k = key(c, r)
      cells[#cells + 1] = { c = c, r = r, raw = sh.cells[k], fmt = sh.fmt[k] }
    end
  end
  return cells
end







function O.copy(sh, c1, r1, c2, r2, tc1, tr1, tc2, tr2)
  tc2, tr2 = tc2 or tc1, tr2 or tr1
  local w, h = c2 - c1 + 1, r2 - r1 + 1
  local src = blockCells(sh, c1, r1, c2, r2)
  local anchors = {}
  if w == 1 and h == 1 then
    for c = tc1, tc2 do for r = tr1, tr2 do anchors[#anchors + 1] = { c, r } end end
  elseif h == 1 then
    for r = tr1, tr2 do anchors[#anchors + 1] = { tc1, r } end
  elseif w == 1 then
    for c = tc1, tc2 do anchors[#anchors + 1] = { c, tr1 } end
  else
    anchors[1] = { tc1, tr1 }
  end
  local n = 0
  for _, a in ipairs(anchors) do
    local dc, dr = a[1] - c1, a[2] - r1
    for _, cell in ipairs(src) do
      local nc, nr = cell.c + dc, cell.r + dr
      if onSheet(nc, nr) then
        local raw = cell.raw and O.shift(cell.raw, dc, dr) or nil
        S.set(sh, nc, nr, raw)
        sh.fmt[key(nc, nr)] = cell.fmt
        n = n + 1
      end
    end
  end
  return n
end



function O.move(sh, c1, r1, c2, r2, tc, tr)
  local dc, dr = tc - c1, tr - r1
  if dc == 0 and dr == 0 then return 0 end
  local w, h = c2 - c1 + 1, r2 - r1 + 1
  if not onSheet(tc + w - 1, tr + h - 1) then return nil, "the block would fall off the sheet" end
  local function inSrc(c, r) return c >= c1 and c <= c2 and r >= r1 and r <= r2 end
  local function inDst(c, r) return c >= tc and c < tc + w and r >= tr and r < tr + h end
  local function one(c, r)
    if inSrc(c, r) then return c + dc, r + dr end
    if inDst(c, r) then return nil end           
    return c, r
  end
  local src = blockCells(sh, c1, r1, c2, r2)
  
  rewriteSheet(sh, one, function(a, b, x, y)
    local n1, m1 = one(a, b)
    local n2, m2 = one(x, y)
    if not n1 or not n2 then return nil end
    return n1, m1, n2, m2
  end)
  for _, cell in ipairs(src) do
    local k = key(cell.c, cell.r)
    cell.raw = sh.cells[k]                      
    sh.cells[k] = nil
    sh.fmt[k] = nil
  end
  for _, cell in ipairs(src) do
    S.set(sh, cell.c + dc, cell.r + dr, cell.raw)
    sh.fmt[key(cell.c + dc, cell.r + dr)] = cell.fmt
  end
  return #src
end



local function relocate(sh, axis, map)
  local cells, fmts = {}, {}
  for k, raw in pairs(sh.cells) do cells[k] = raw end
  for k, f in pairs(sh.fmt) do fmts[k] = f end
  sh.cells, sh.fmt = {}, {}
  for k, raw in pairs(cells) do
    local c, r = unkey(k)
    local nc, nr = map(c, r)
    if nc then sh.cells[key(nc, nr)] = raw end
  end
  for k, f in pairs(fmts) do
    local c, r = unkey(k)
    local nc, nr = map(c, r)
    if nc then sh.fmt[key(nc, nr)] = f end
  end
  if axis == "col" then
    local w = {}
    for c, v in pairs(sh.colw) do
      local nc = map(c, 1)
      if nc then w[nc] = v end
    end
    sh.colw = w
  end
end

local function lineOps(axis)
  local function pick(c, r) if axis == "row" then return r end return c end
  local function put(c, r, v) if axis == "row" then return c, v end return v, r end

  local function insert(sh, at, n)
    n = n or 1
    local function one(c, r)
      local v = pick(c, r)
      if v >= at then v = v + n end
      local nc, nr = put(c, r, v)
      if not onSheet(nc, nr) then return nil end
      return nc, nr
    end
    rewriteSheet(sh, one, function(a, b, x, y)
      local n1, m1 = one(a, b)
      local n2, m2 = one(x, y)
      if not n1 then return nil end
      if not n2 then n2, m2 = put(x, y, axis == "row" and S.MAX_ROWS or S.MAX_COLS) end
      return n1, m1, n2, m2
    end)
    relocate(sh, axis, one)
  end

  local function delete(sh, at, n)
    n = n or 1
    local last = at + n - 1
    local function one(c, r)
      local v = pick(c, r)
      if v >= at and v <= last then return nil end
      if v > last then v = v - n end
      return put(c, r, v)
    end
    rewriteSheet(sh, one, function(a, b, x, y)
      local s, e = pick(a, b), pick(x, y)
      if s > e then s, e = e, s end
      
      local ns = (s >= at and s <= last) and at or (s > last and s - n or s)
      local ne = (e >= at and e <= last) and (at - 1) or (e > last and e - n or e)
      if ns > ne then return nil end
      local n1, m1 = put(a, b, ns)
      local n2, m2 = put(x, y, ne)
      return n1, m1, n2, m2
    end)
    relocate(sh, axis, one)
  end
  return insert, delete
end
O.insertRows, O.deleteRows = lineOps("row")
O.insertCols, O.deleteCols = lineOps("col")





local function compareKeys(a, b, asc)
  local ta = (a == nil or a == "") and 3 or (type(a) == "number" and 1 or 2)
  local tb = (b == nil or b == "") and 3 or (type(b) == "number" and 1 or 2)
  if ta ~= tb then return (ta < tb) and -1 or 1 end
  if ta == 3 then return 0 end
  if ta == 2 then a, b = tostring(a):lower(), tostring(b):lower() end
  if a == b then return 0 end
  local lt = a < b
  if not asc then lt = not lt end
  return lt and -1 or 1
end



function O.sort(sh, c1, r1, c2, r2, k1, asc1, k2, asc2)
  local ctx = S.evaluator(sh)
  local rows = {}
  for r = r1, r2 do
    local v1 = ctx.get(k1, r)
    local v2 = k2 and ctx.get(k2, r) or nil
    if S.isErr(v1) then v1 = v1.e end
    if S.isErr(v2) then v2 = v2.e end
    rows[#rows + 1] = { r = r, k1 = v1, k2 = v2 }
  end
  
  for i = 2, #rows do
    local item = rows[i]
    local j = i - 1
    while j >= 1 do
      local cmp = compareKeys(item.k1, rows[j].k1, asc1 ~= false)
      if cmp == 0 and k2 then cmp = compareKeys(item.k2, rows[j].k2, asc2 ~= false) end
      if cmp < 0 then rows[j + 1] = rows[j]; j = j - 1 else break end
    end
    rows[j + 1] = item
  end
  local snapshot = {}
  for _, row in ipairs(rows) do
    local cells = {}
    for c = c1, c2 do
      local k = key(c, row.r)
      cells[c] = { raw = sh.cells[k], fmt = sh.fmt[k] }
    end
    snapshot[#snapshot + 1] = { from = row.r, cells = cells }
  end
  for i, row in ipairs(snapshot) do
    local to = r1 + i - 1
    for c = c1, c2 do
      local cell = row.cells[c]
      local raw = cell.raw and O.shift(cell.raw, 0, to - row.from) or nil
      S.set(sh, c, to, raw)
      sh.fmt[key(c, to)] = cell.fmt
    end
  end
  return #rows
end




function O.fill(sh, c1, r1, c2, r2, start, step, stop)
  step = step or 1
  local v, n = start, 0
  for c = c1, c2 do
    for r = r1, r2 do
      if stop and ((step >= 0 and v > stop) or (step < 0 and v < stop)) then return n end
      S.set(sh, c, r, S.toStr(v))
      n = n + 1
      v = v + step
    end
  end
  return n
end



function O.values(sh, c1, r1, c2, r2, tc, tr)
  local ctx = S.evaluator(sh)
  local out = {}
  for c = c1, c2 do
    for r = r1, r2 do
      local v = ctx.get(c, r)
      local raw
      if v == nil then raw = nil
      elseif S.isErr(v) then raw = "'" .. v.e
      elseif type(v) == "number" then raw = S.toStr(v)
      else raw = "'" .. tostring(v) end
      out[#out + 1] = { c = tc + (c - c1), r = tr + (r - r1), raw = raw }
    end
  end
  for _, cell in ipairs(out) do S.set(sh, cell.c, cell.r, cell.raw) end
  return #out
end


function O.erase(sh, c1, r1, c2, r2)
  local n = 0
  for c = c1, c2 do
    for r = r1, r2 do
      if sh.cells[key(c, r)] then sh.cells[key(c, r)] = nil; n = n + 1 end
    end
  end
  return n
end


function O.format(sh, c1, r1, c2, r2, code)
  for c = c1, c2 do
    for r = r1, r2 do sh.fmt[key(c, r)] = code end
  end
end


function O.label(sh, c1, r1, c2, r2, p)
  local n = 0
  for c = c1, c2 do
    for r = r1, r2 do
      local raw = sh.cells[key(c, r)]
      if raw then
        local kind, body, align = S.classify(raw)
        if kind == "label" and align ~= "REP" then
          sh.cells[key(c, r)] = p .. body; n = n + 1
        end
      end
    end
  end
  return n
end



function O.validName(name)
  if type(name) ~= "string" or not name:match("^%a[%w_]*$") or #name > 15 then return false end
  if S.parseRef(name) then return false end
  if S.FUNCS[name:upper()] then return false end
  if name:upper() == "TRUE" or name:upper() == "FALSE" then return false end
  return true
end

return O
