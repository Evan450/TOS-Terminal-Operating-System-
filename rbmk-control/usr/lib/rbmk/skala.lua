
























local S = {}

S.VERSION = "0.2.0"
















S.PARAMS = {
  { key = "N", label = "POWER",     field = "flux",     unit = "",
    full = 10000, limit = "fluxScram", step = 4 },
  { key = "T", label = "CORE TEMP", field = "temp",     unit = "C",
    full = 1000,  limit = "tempScram", step = 1 },
  { key = "X", label = "STEAM",     field = "steam",    unit = "%",
    full = 100,   step = 0.01 },
  { key = "K", label = "ROD DEPTH", field = "rodDepth", unit = "%",
    full = 100,   step = 0.01 },
  { key = "G", label = "COOLANT",   field = "water",    unit = "%",
    full = 100,   limit = "waterMin", invert = true, step = 0.01 },
}


function S.param(key)
  if type(key) ~= "string" then return nil end
  key = key:upper()
  for _, p in ipairs(S.PARAMS) do if p.key == key then return p end end
  return nil
end


function S.paramKeys()
  local t = {}
  for i, p in ipairs(S.PARAMS) do t[i] = p.key end
  return t
end







S.BANDS = {
  { 0.00, 0x0080FF, "cold"   },
  { 0.40, 0x00FF00, "normal" },
  { 0.70, 0xFFFF00, "high"   },
  { 0.85, 0xFF8000, "warn"   },
  { 1.00, 0xFF0000, "alarm"  },
}
S.COLOR_MISSING = 0x666666   











function S.fractionOf(value, param, limits)
  if type(value) ~= "number" or value ~= value then return nil end
  if not param then return nil end
  local top = param.full
  if param.limit and limits and type(limits[param.limit]) == "number" then
    top = limits[param.limit]
  end
  if param.invert then
    
    local healthy = param.full or 100
    --! A config where the minimum is at or above the healthy end is
    --! nonsense; fall back to a tenth of full rather than divide by
    --! zero and paint the whole map one colour.
    if not top or top >= healthy then top = healthy * 0.1 end
    if value >= healthy then return 0 end
    if value <= top then return 1 end
    return (healthy - value) / (healthy - top)
  end
  if not top or top <= 0 then return nil end
  local f = value / top
  if f < 0 then f = 0 end
  if f > 1 then f = 1 end
  return f
end



function S.bandOf(value, param, limits)
  local f = S.fractionOf(value, param, limits)
  if f == nil then return S.COLOR_MISSING, "missing" end
  local col, name = S.BANDS[1][2], S.BANDS[1][3]
  for _, b in ipairs(S.BANDS) do
    if f >= b[1] then col, name = b[2], b[3] end
  end
  return col, name
end







--! The bounds are ASYMMETRIC on purpose, and getting that wrong is the
--! bug this was caught by: a minus sign costs a column, so the widest
--! printable integer is 9999 going up but only -999 going down. Testing
--! math.abs(v) against one bound lets -9999 through, and "%4d" then
--! renders FIVE characters and shifts the whole row.
function S.cellText(v)
  if type(v) ~= "number" or v ~= v then return "----" end   
  if v > -999.5 and v < 9999.5 then
    return string.format("%4d", math.floor(v + 0.5))
  elseif v > -99500 and v < 999500 then
    return string.format("%3.0fk", v / 1000)
  elseif v >= 999500 and v < 999500000 then
    return string.format("%3.0fM", v / 1000000)
  end
  --! Deliberately not carried further on the negative side: a channel
  --! reading below -99,500 is nonsense, and "-BIG" says so honestly
  --! rather than rounding it to a plausible-looking " -0M".
  return v < 0 and "-BIG" or "+BIG"
end









function S.isChannel(x, y, grid)
  grid = grid or {}
  local w, h = grid.w or 15, grid.h or 15
  if x < 1 or y < 1 or x > w or y > h then return false end
  if grid.mask then return grid.mask[x .. "," .. y] == true end
  if grid.shape == "circle" then
    local cx, cy = (w + 1) / 2, (h + 1) / 2
    local rx, ry = w / 2, h / 2
    local dx, dy = (x - cx) / rx, (y - cy) / ry
    return (dx * dx + dy * dy) <= 1.0
  end
  return true
end


function S.channelCount(grid)
  grid = grid or {}
  local n = 0
  for y = 1, grid.h or 15 do
    for x = 1, grid.w or 15 do
      if S.isChannel(x, y, grid) then n = n + 1 end
    end
  end
  return n
end




S.RAIL_PREF = 22    
S.RAIL_MIN  = 10    
S.CELL_MAX  = 5     
S.CELL_MIN  = 2     












function S.layout(W, H, grid)
  grid = grid or {}
  local gw, gh = grid.w or 15, grid.h or 15
  local L = { gridW = gw, gridH = gh }

  
  
  L.headerH = 2
  L.footerH = 2
  local needH = L.headerH + 1 + gh + 1 + L.footerH
  if H < needH then
    return { ok = false, why = string.format(
      "screen is %d rows; a %dx%d core map needs %d", H, gw, gh, needH) }
  end

  
  L.rulerW = #tostring(gh)
  local function widthFor(rail, cell)
    return L.rulerW + 1 + gw * cell + (rail > 0 and (1 + rail) or 0)
  end
  --! ORDER MATTERS, and it is the opposite of what it first looks
  --! like. Cell width is the OUTER loop, so a numeric map wins over a
  --! wide rail: on an 80-column screen a 15x15 core fits at 5 columns
  --! per cell only if the rail goes, and a map of numbers with the
  --! parameter named in the header beats a map of anonymous colour
  --! blocks next to a tidy menu. The rail is a menu; the map is the
  --! instrument. (The renderer always prints the selected parameter in
  --! the header, so a railless layout is never ambiguous.)
  local rail, cell
  for c = S.CELL_MAX, S.CELL_MIN, -1 do
    for _, r in ipairs({ S.RAIL_PREF, S.RAIL_MIN, 0 }) do
      if widthFor(r, c) <= W then rail, cell = r, c; break end
    end
    if cell then break end
  end
  if not cell then
    return { ok = false, why = string.format(
      "screen is %d columns; a %dx%d core map needs %d",
      W, gw, gh, widthFor(0, S.CELL_MIN)) }
  end

  L.ok      = true
  L.W, L.H  = W, H
  L.railW   = rail
  L.cellW   = cell
  --! Below 5 a cell cannot hold "-999" plus a gap, so it stops being a
  --! number and becomes a colour block. Deciding that here means the
  --! renderer never has to, and the legend can say so too.
  L.numeric = (cell >= 5)
  L.rulerY  = L.headerH + 1
  L.mapY    = L.rulerY + 1
  L.mapX    = L.rulerW + 2
  L.railX   = (rail > 0) and (W - rail + 1) or nil
  L.statusY = L.mapY + gh + 1
  return L
end



function S.cellPos(L, x, y, grid)
  if not (L and L.ok) then return nil end
  if grid and not S.isChannel(x, y, grid) then return nil end
  if x < 1 or y < 1 or x > L.gridW or y > L.gridH then return nil end
  return L.mapX + (x - 1) * L.cellW, L.mapY + (y - 1)
end




function S.cellAt(L, px, py, grid)
  if not (L and L.ok) then return nil end
  local dy = py - L.mapY
  if dy < 0 or dy >= L.gridH then return nil end
  local dx = px - L.mapX
  if dx < 0 then return nil end
  local cx = math.floor(dx / L.cellW) + 1
  if cx > L.gridW then return nil end
  --! The separator column belongs to no cell. Without this a click in
  --! the gap picks the cell to its left, which reads fine right up
  --! until an operator is one column off about which channel they are
  --! inspecting.
  if L.cellW > 4 and (dx % L.cellW) >= 4 then return nil end
  local cy = dy + 1
  if grid and not S.isChannel(cx, cy, grid) then return nil end
  return cx, cy
end







function S.railRows(L, selectedKey)
  local rows = {}
  if not (L and L.ok and L.railW and L.railW > 0) then return rows end
  local wide = L.railW >= S.RAIL_PREF
  for _, p in ipairs(S.PARAMS) do
    local text
    if wide then text = p.key .. "  " .. p.label
    else text = p.key .. " " .. p.label:sub(1, math.max(1, L.railW - 2)) end
    rows[#rows + 1] = {
      key = p.key, text = text, param = p,
      selected = (p.key == selectedKey),
    }
  end
  return rows
end







function S.readout(snap, chan, param, limits)
  local out = {}
  local src = chan or snap or {}
  for _, p in ipairs(S.PARAMS) do
    local v = src[p.field]
    local col, band = S.bandOf(v, p, limits)
    local shown
    if type(v) ~= "number" then shown = "----"
    elseif math.abs(v) >= 1000 then shown = S.cellText(v)
    else shown = string.format("%.1f", v) end
    out[#out + 1] = {
      key = p.key,
      text = p.key .. " " .. shown .. (p.unit ~= "" and (" " .. p.unit) or ""),
      band = band, color = col,
      selected = (param ~= nil and p.key == param.key),
    }
  end
  return out
end







function S.legend(param, limits)
  local out = {}
  local top = param and param.full
  if param and param.limit and limits and type(limits[param.limit]) == "number" then
    top = limits[param.limit]
  end
  for _, b in ipairs(S.BANDS) do
    local at
    if param and top then
      if param.invert then
        local healthy = param.full or 100
        at = healthy - b[1] * (healthy - top)
      else
        at = b[1] * top
      end
    end
    out[#out + 1] = { name = b[3], color = b[2], at = at }
  end
  return out
end

return S
