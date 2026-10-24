-- ╔══════════════════════════════════════════════════════════════╗
-- ║  calc — the operations that rewrite formulas                 ║
-- ║                                                              ║
-- ║  Copy, Move, Insert, Delete and Sort all have to answer the  ║
-- ║  same question 1-2-3 answers: when a cell moves, what do the ║
-- ║  formulas that point at it — or inside it — now say? The     ║
-- ║  answer is one function, rewrite(), that walks a formula's   ║
-- ║  TEXT and hands every reference to a callback, so each       ║
-- ║  operation is only its own rule:                             ║
-- ║                                                              ║
-- ║    Copy    a relative reference moves with the copy; a $     ║
-- ║            part stays put                                    ║
-- ║    Move    whatever pointed INTO the moved block follows it, ║
-- ║            $ or not; what pointed at a cell the block landed ║
-- ║            on is #REF!                                       ║
-- ║    Insert  everything at or past the new row/column moves on ║
-- ║    Delete  a reference into the deleted rows is #REF!; a     ║
-- ║            range that loses an end shrinks to what is left   ║
-- ║    Sort    each row's formulas move like a Copy of the row   ║
-- ║                                                              ║
-- ║  Rewriting the text (not a parsed tree) keeps what the user  ║
-- ║  typed — spacing, @, .., $ — everywhere it is not changing.  ║
-- ║  Pure: a sheet in, the same sheet changed.                   ║
-- ╚══════════════════════════════════════════════════════════════╝

local S = require("calc.sheet")
local O = {}

local key, unkey = S._key, S.unkey

-- ── The reference walker ──────────────────────────────────────────────
-- A reference at src[i], as refAt in sheet.lua: "$A$1", "B12", never the
-- front of a longer word ("LOG10").
local function refAt(src, i)
  local word = src:match("^%$?%a+%$?%d+", i)
  if not word then return nil end
  if src:sub(i + #word, i + #word):match("[%w_]") then return nil end
  if not S.parseRef(word) then return nil end
  return word
end

--- Rewrite every reference in formula text `src`.
---   onRef(c, r, absC, absR)                 -> c, r   (nil = #REF!)
---   onRange(c1, r1, c2, r2)                 -> c1, r1, c2, r2 (nil = #REF!)
--- A range's two ends keep their own $ flags. Returns the new text and
--- whether anything changed.
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
      -- A whole number, exponent included: 1E5 is not a reference to E5.
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

--- The text a formula becomes when copied dc columns right and dr rows
--- down: relative parts move, $ parts stay.
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

-- Every formula on the sheet, rewritten with the same pair of rules, and
-- every range name moved with them.
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

-- ── Copy ──────────────────────────────────────────────────────────────
--- /Copy FROM (c1..r2) TO a range. A one-cell source fills the whole
--- destination; a one-row source is repeated down every destination row,
--- a one-column source across every column; anything else is placed once
--- at the destination's top-left. Formats travel with the cells.
--- Returns the number of cells written.
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

-- ── Move ──────────────────────────────────────────────────────────────
--- /Move FROM (c1..r2) TO the cell (tc, tr).
function O.move(sh, c1, r1, c2, r2, tc, tr)
  local dc, dr = tc - c1, tr - r1
  if dc == 0 and dr == 0 then return 0 end
  local w, h = c2 - c1 + 1, r2 - r1 + 1
  if not onSheet(tc + w - 1, tr + h - 1) then return nil, "the block would fall off the sheet" end
  local function inSrc(c, r) return c >= c1 and c <= c2 and r >= r1 and r <= r2 end
  local function inDst(c, r) return c >= tc and c < tc + w and r >= tr and r < tr + h end
  local function one(c, r)
    if inSrc(c, r) then return c + dc, r + dr end
    if inDst(c, r) then return nil end           -- what was there is gone
    return c, r
  end
  local src = blockCells(sh, c1, r1, c2, r2)
  -- Rewrite first (cell contents still at their old addresses), then move.
  rewriteSheet(sh, one, function(a, b, x, y)
    local n1, m1 = one(a, b)
    local n2, m2 = one(x, y)
    if not n1 or not n2 then return nil end
    return n1, m1, n2, m2
  end)
  for _, cell in ipairs(src) do
    local k = key(cell.c, cell.r)
    cell.raw = sh.cells[k]                      -- as rewritten
    sh.cells[k] = nil
    sh.fmt[k] = nil
  end
  for _, cell in ipairs(src) do
    S.set(sh, cell.c + dc, cell.r + dr, cell.raw)
    sh.fmt[key(cell.c + dc, cell.r + dr)] = cell.fmt
  end
  return #src
end

-- ── Insert and delete ─────────────────────────────────────────────────
-- One routine for rows and columns: `axis` says which coordinate moves.
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
      -- An end inside the deleted lines moves to the nearest survivor.
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

-- ── Sort ──────────────────────────────────────────────────────────────
-- 1-2-3's order: numbers before labels, labels alphabetically, blank keys
-- last; ties keep their order (a stable sort, done by hand because
-- table.sort is not stable).
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

--- /Data Sort: the rows of c1..r2 by the value in column `k1` (and `k2`
--- for ties). Each row's formulas move like a copy of the row.
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
  -- Insertion sort: stable, and a sort range is never large.
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

-- ── Fill, values, erase ───────────────────────────────────────────────
--- /Data Fill: start, start+step, ... down each column in turn, stopping
--- at `stop` (or the end of the range). Returns the number written.
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

--- /Range Value: the CURRENT values of c1..r2 written as constants at
--- (tc, tr) — a formula becomes the number or text it shows.
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

--- /Range Erase: contents go, formats stay (as in 1-2-3).
function O.erase(sh, c1, r1, c2, r2)
  local n = 0
  for c = c1, c2 do
    for r = r1, r2 do
      if sh.cells[key(c, r)] then sh.cells[key(c, r)] = nil; n = n + 1 end
    end
  end
  return n
end

--- /Range Format. `code` nil resets the range to the global format.
function O.format(sh, c1, r1, c2, r2, code)
  for c = c1, c2 do
    for r = r1, r2 do sh.fmt[key(c, r)] = code end
  end
end

--- /Range Label: give every label in the range prefix `p` (' " ^).
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

--- A range name: letters, digits and _ starting with a letter, and not
--- something that reads as a cell address or a function.
function O.validName(name)
  if type(name) ~= "string" or not name:match("^%a[%w_]*$") or #name > 15 then return false end
  if S.parseRef(name) then return false end
  if S.FUNCS[name:upper()] then return false end
  if name:upper() == "TRUE" or name:upper() == "FALSE" then return false end
  return true
end

return O
