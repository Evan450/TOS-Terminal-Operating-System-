-- ╔══════════════════════════════════════════════════════════════╗
-- ║  calc — /Graph, drawn in characters (pure)                   ║
-- ║                                                              ║
-- ║  1-2-3 drew its graphs on a separate graphics screen; calc   ║
-- ║  draws them in the text grid it already has, which is all an ║
-- ║  OpenComputers screen is. A bar graph or a line graph of up  ║
-- ║  to three data ranges (A, B, C) against the X range's        ║
-- ║  labels, with a scaled Y axis and the two titles.            ║
-- ║                                                              ║
-- ║  render() returns rows of text and, beside them, which       ║
-- ║  series owns each character, so the screen can colour them   ║
-- ║  and a test can read them back.                              ║
-- ╚══════════════════════════════════════════════════════════════╝

local S = require("calc.sheet")
local G = {}

G.SERIES = { "a", "b", "c" }
-- Bars: a full block and a lower half block. In monochrome each series
-- gets its own character instead, since colour cannot tell them apart.
G.BAR = { full = "\226\150\136", half = "\226\150\132" }
G.MONO_BAR = { a = "#", b = "=", c = "%" }
G.POINT = { a = "*", b = "o", c = "+" }

--- The values of a range, in reading order (down a column, or across a
--- row). Text and blanks are nil in a data range, and text in X.
function G.values(sh, ctx, spec, asText)
  if not spec or spec == "" then return nil end
  local c1, r1, c2, r2
  if sh.names[spec:upper()] then
    local rg = sh.names[spec:upper()]
    c1, r1, c2, r2 = rg[1], rg[2], rg[3], rg[4]
  else
    c1, r1, c2, r2 = S.parseRange(spec)
  end
  if not c1 then return nil end
  local out = {}
  local n = 0
  if (r2 - r1) >= (c2 - c1) then
    for r = r1, r2 do for c = c1, c2 do
      n = n + 1
      local v = ctx.get(c, r)
      if asText then out[n] = (v ~= nil and not S.isErr(v)) and S.toStr(v) or ""
      else out[n] = type(v) == "number" and v or nil end
    end end
  else
    for c = c1, c2 do for r = r1, r2 do
      n = n + 1
      local v = ctx.get(c, r)
      if asText then out[n] = (v ~= nil and not S.isErr(v)) and S.toStr(v) or ""
      else out[n] = type(v) == "number" and v or nil end
    end end
  end
  out.n = n
  return out
end

--- Everything /Graph View needs from the sheet.
function G.collect(sh, ctx)
  local g = sh.graph or {}
  local d = { type = g.type or "bar", title1 = g.title1, title2 = g.title2, series = {} }
  d.x = G.values(sh, ctx, g.x, true)
  local n = d.x and d.x.n or 0
  for _, s in ipairs(G.SERIES) do
    local v = G.values(sh, ctx, g[s])
    if v then d.series[#d.series + 1] = { key = s, v = v }; if v.n > n then n = v.n end end
  end
  d.n = n
  return d
end

-- A tidy axis top: 1, 2 or 5 times a power of ten at or above x.
local function niceCeil(x)
  if x <= 0 then return 0 end
  local p = 10 ^ math.floor(math.log(x, 10))
  for _, m in ipairs({ 1, 2, 5, 10 }) do
    if m * p >= x - 1e-9 then return m * p end
  end
  return 10 * p
end
G.niceCeil = niceCeil

local function axisLabel(v)
  local s
  if math.abs(v) >= 1e6 then s = string.format("%.3g", v)
  elseif v == math.floor(v) then s = string.format("%d", v)
  else s = string.format("%.2f", v) end
  return s
end

--- Draw `d` (from collect) into a w x h block. Returns rows (strings,
--- one per line, exactly w columns) and marks (marks[y][x] = series key,
--- "axis" or "title"), or nil and a reason.
function G.render(d, w, h, mono)
  if #d.series == 0 then return nil, "no data range: set A (and B, C) first" end
  if d.n == 0 then return nil, "the data ranges are empty" end
  local rows, marks = {}, {}
  for y = 1, h do rows[y] = {}; marks[y] = {} for x = 1, w do rows[y][x] = " " end end
  local function put(x, y, ch, m)
    if x >= 1 and x <= w and y >= 1 and y <= h then rows[y][x] = ch; marks[y][x] = m end
  end
  local function text(x, y, s, m)
    local i = 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do put(x + i, y, ch, m); i = i + 1 end
  end

  -- Titles.
  local top = 1
  for _, t in ipairs({ d.title1, d.title2 }) do
    if t and t ~= "" then
      text(math.max(1, math.floor((w - #t) / 2) + 1), top, t:sub(1, w), "title")
      top = top + 1
    end
  end
  if top > 1 then top = top + 1 end

  -- The scale: always include zero, 1-2-3 style.
  local lo, hi = 0, 0
  for _, s in ipairs(d.series) do
    for i = 1, d.n do
      local v = s.v[i]
      if v then if v < lo then lo = v end; if v > hi then hi = v end end
    end
  end
  hi = niceCeil(hi)
  lo = -niceCeil(-lo)
  if hi == lo then hi = lo + 1 end

  local labelW = math.max(#axisLabel(hi), #axisLabel(lo)) + 1
  local plotX = labelW + 2
  local bottom = h - 2                 -- X labels and the legend below
  local plotH = bottom - top + 1
  if plotH < 3 or w - plotX < d.n then return nil, "the screen is too small for this graph" end
  local plotW = w - plotX + 1

  local function rowOf(v)              -- the row a value reaches, fractional
    return bottom - (v - lo) / (hi - lo) * (plotH - 1)
  end
  -- Axes and their labels.
  for y = top, bottom do put(plotX - 1, y, "|", "axis") end
  local zeroY = math.floor(rowOf(0) + 0.5)
  for x = plotX, w do put(x, zeroY, "-", "axis") end
  put(plotX - 1, zeroY, "+", "axis")
  text(1, top, string.rep(" ", labelW - #axisLabel(hi)) .. axisLabel(hi), "axis")
  text(1, bottom, string.rep(" ", labelW - #axisLabel(lo)) .. axisLabel(lo), "axis")
  if zeroY ~= top and zeroY ~= bottom then text(1, zeroY, string.rep(" ", labelW - 1) .. "0", "axis") end

  local slot = math.floor(plotW / d.n)
  local k = #d.series
  if d.type == "line" then
    for _, s in ipairs(d.series) do
      local px, py
      for i = 1, d.n do
        local v = s.v[i]
        if v then
          local x = plotX + (i - 1) * slot + math.floor(slot / 2)
          local y = math.floor(rowOf(v) + 0.5)
          -- Join to the previous point with dots, then mark this one.
          if px then
            local steps = math.max(math.abs(x - px), math.abs(y - py))
            for t = 1, steps - 1 do
              local ix = px + math.floor((x - px) * t / steps + 0.5)
              local iy = py + math.floor((y - py) * t / steps + 0.5)
              if rows[iy] and rows[iy][ix] == " " then put(ix, iy, ".", s.key) end
            end
          end
          put(x, y, G.POINT[s.key], s.key)
          px, py = x, y
        else
          px, py = nil, nil
        end
      end
    end
  else
    local bw = math.max(1, math.floor((slot - 1) / k))
    for si, s in ipairs(d.series) do
      for i = 1, d.n do
        local v = s.v[i]
        if v and v ~= 0 then
          local x0 = plotX + (i - 1) * slot + (si - 1) * bw
          local yv = rowOf(v)
          local full = mono and G.MONO_BAR[s.key] or G.BAR.full
          local half = mono and G.MONO_BAR[s.key] or G.BAR.half
          if v > 0 then
            -- From the zero line up to the value, a half block on top.
            local yTop = math.floor(yv + 0.5)
            for y = zeroY - 1, yTop, -1 do
              for x = x0, x0 + bw - 1 do put(x, y, full, s.key) end
            end
            if yv - math.floor(yv) >= 0.25 and yv - math.floor(yv) < 0.75 then
              for x = x0, x0 + bw - 1 do put(x, math.floor(yv), half, s.key) end
            end
          else
            for y = zeroY + 1, math.floor(yv + 0.5) do
              for x = x0, x0 + bw - 1 do put(x, y, full, s.key) end
            end
          end
        end
      end
    end
  end

  -- X labels, cut to their slot.
  if d.x then
    for i = 1, d.n do
      local lab = (d.x[i] or ""):sub(1, math.max(1, slot - 1))
      text(plotX + (i - 1) * slot, bottom + 1, lab, "axis")
    end
  end
  -- Legend.
  local x = plotX
  for _, s in ipairs(d.series) do
    local sym = d.type == "line" and G.POINT[s.key] or (mono and G.MONO_BAR[s.key] or G.BAR.full)
    put(x, h, sym, s.key)
    text(x + 2, h, s.key:upper(), "axis")
    x = x + 5
  end

  local out = {}
  for y = 1, h do out[y] = table.concat(rows[y]) end
  return out, marks
end

return G
