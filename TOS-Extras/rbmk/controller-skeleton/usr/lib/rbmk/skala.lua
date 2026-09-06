-- ╔══════════════════════════════════════════════════════════════╗
-- ║  rbmk.skala — the SKALA-style information panel (PURE)       ║
-- ║                                                              ║
-- ║  Modelled on the RBMK operator's information-output console: ║
-- ║  a coordinate-ruled CORE MAP showing one reading per channel,║
-- ║  with a right-hand rail of single-letter parameter keys that ║
-- ║  swap which reading the map is showing.                      ║
-- ║                                                              ║
-- ║  Everything here is arithmetic and strings. Nothing in this  ║
-- ║  file touches a GPU, a component or the network — the        ║
-- ║  renderer (rbmk-skala.lua) and the OpenOS satellite both     ║
-- ║  draw from THIS, so the two cannot disagree about where a    ║
-- ║  cell is or what colour it should be. That is the whole      ║
-- ║  reason for the split: a display wall whose panes each       ║
-- ║  compute their own layout is a wall that drifts.             ║
-- ║                                                              ║
-- ║  SAFETY POSTURE. A panel is a READ-ONLY consumer (Plan.md    ║
-- ║  §Safety rule 1). There is no code path from here to a rod:  ║
-- ║  the parameter keys select what is DISPLAYED and nothing     ║
-- ║  else. The one thing this file is safety-relevant for is     ║
-- ║  colour — see bandOf(): a reading that is dangerous because  ║
-- ║  it is LOW must not be drawn in the same calm blue as a      ║
-- ║  reading that is safe because it is low.                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local S = {}

S.VERSION = "0.2.0"

-- ============================================================
-- Parameters — the rail's lettered keys
-- ============================================================
-- `key`     the single letter on the rail (SKALA's parameter keys)
-- `label`   what the rail spells out
-- `field`   which normalized channel reading it maps onto
-- `unit`    appended in the readout, never in a map cell (4 chars only)
-- `full`    the top of the colour scale when no configured limit applies
-- `limit`   name of the /etc/rbmk.cfg limit that IS the top of the
--           scale, when one exists — so recolouring follows the
--           operator's own scram threshold rather than a constant
--           chosen here
-- `invert`  TRUE when LOW is the dangerous end. Coolant flow is the
--           reason this field exists; see fractionOf().
-- `step`    wire quantisation (see packColumns in rbmk.core)
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

--- Look a parameter up by its rail letter (case-insensitive).
function S.param(key)
  if type(key) ~= "string" then return nil end
  key = key:upper()
  for _, p in ipairs(S.PARAMS) do if p.key == key then return p end end
  return nil
end

--- The rail letters in order, e.g. for a help line.
function S.paramKeys()
  local t = {}
  for i, p in ipairs(S.PARAMS) do t[i] = p.key end
  return t
end

-- ============================================================
-- Colour bands
-- ============================================================
-- Five bands, low to high, each `{ atFraction, colour, name }`. Chosen
-- from colours a tier-2 GPU can actually show, so a cheap satellite
-- renders the same picture a tier-3 console does.
S.BANDS = {
  { 0.00, 0x0080FF, "cold"   },
  { 0.40, 0x00FF00, "normal" },
  { 0.70, 0xFFFF00, "high"   },
  { 0.85, 0xFF8000, "warn"   },
  { 1.00, 0xFF0000, "alarm"  },
}
S.COLOR_MISSING = 0x666666   -- "----": no reading, which is not a zero reading

--- Where does `value` sit on `param`'s scale, 0..1? `limits` is the
--- merged limit table (core.mergeLimits); a param naming a limit uses
--- it, so the colour ramp tops out exactly where the controller would
--- shut the reactor down rather than at a number picked here.
---
--- INVERTED PARAMETERS. Coolant is the case: 100% is healthy and 0% is
--- a scram condition, so the fraction is measured DOWNWARD from the
--- healthy end and `waterMin` is the point that reads full alarm.
--- Without this a dry loop would draw in the same blue as a cold core
--- — the display would be calmest at the moment it should be loudest.
function S.fractionOf(value, param, limits)
  if type(value) ~= "number" or value ~= value then return nil end
  if not param then return nil end
  local top = param.full
  if param.limit and limits and type(limits[param.limit]) == "number" then
    top = limits[param.limit]
  end
  if param.invert then
    -- Here `top` is the MINIMUM acceptable value (e.g. waterMin).
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

--- Band (colour, name) for a reading. Missing reads as MISSING, never
--- as the bottom band: a channel we cannot see is not a cold channel.
function S.bandOf(value, param, limits)
  local f = S.fractionOf(value, param, limits)
  if f == nil then return S.COLOR_MISSING, "missing" end
  local col, name = S.BANDS[1][2], S.BANDS[1][3]
  for _, b in ipairs(S.BANDS) do
    if f >= b[1] then col, name = b[2], b[3] end
  end
  return col, name
end

-- ============================================================
-- Cell text — exactly 4 characters, always
-- ============================================================
--- The map is a fixed grid: a cell that renders 5 characters shifts
--- every cell to its right and the ruler stops meaning anything. So the
--- width is clamped by construction here and pinned by test.
--! The bounds are ASYMMETRIC on purpose, and getting that wrong is the
--! bug this was caught by: a minus sign costs a column, so the widest
--! printable integer is 9999 going up but only -999 going down. Testing
--! math.abs(v) against one bound lets -9999 through, and "%4d" then
--! renders FIVE characters and shifts the whole row.
function S.cellText(v)
  if type(v) ~= "number" or v ~= v then return "----" end   -- nil, non-number, NaN
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

-- ============================================================
-- Core geometry
-- ============================================================
--- Which grid positions are actual channels. HBM's RBMK is a square
--- grid, so "square" is the default and the honest one; "circle"
--- inscribes the round core of an RBMK-1000 for operators who want the
--- historical shape. `grid.mask` (a set of "x,y" keys) overrides both,
--- for a reactor whose real footprint is neither.
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

--- How many channels a grid actually has (the map's denominator).
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

-- ============================================================
-- Layout
-- ============================================================
S.RAIL_PREF = 22    -- comfortable rail: letter + spelled-out label
S.RAIL_MIN  = 10    -- cramped rail: letter + truncated label
S.CELL_MAX  = 5     -- 4 chars + 1 separator column
S.CELL_MIN  = 2     -- 4 chars no longer fit; cells become colour blocks

--- Work out where everything goes on a WxH screen.
---
--- Returns a table with `ok = true` and the geometry, or `ok = false`
--- and a `why` that NAMES THE SIZE NEEDED. A panel that only says "too
--- small" sends the operator away to guess at resolutions; the point of
--- failing here rather than in the renderer is that this can do the
--- arithmetic and tell them the number.
---
--- Cell width degrades before the rail does, and the rail narrows
--- before it disappears, because the parameter you are looking at is
--- the one thing a reading is meaningless without.
function S.layout(W, H, grid)
  grid = grid or {}
  local gw, gh = grid.w or 15, grid.h or 15
  local L = { gridW = gw, gridH = gh }

  -- Vertical: 2 header rows + 1 column ruler + gh map rows + 1 rule +
  -- 2 status rows.
  L.headerH = 2
  L.footerH = 2
  local needH = L.headerH + 1 + gh + 1 + L.footerH
  if H < needH then
    return { ok = false, why = string.format(
      "screen is %d rows; a %dx%d core map needs %d", H, gw, gh, needH) }
  end

  -- Horizontal: left ruler (row numbers), the grid, then the rail.
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

--- Screen position of a channel's cell. nil for a position that is not
--- a channel in this grid.
function S.cellPos(L, x, y, grid)
  if not (L and L.ok) then return nil end
  if grid and not S.isChannel(x, y, grid) then return nil end
  if x < 1 or y < 1 or x > L.gridW or y > L.gridH then return nil end
  return L.mapX + (x - 1) * L.cellW, L.mapY + (y - 1)
end

--- The inverse: which channel is under a click? nil when the point is
--- not over a cell. (The panel is read-only, so a click SELECTS a
--- channel for the readout — it never actuates anything.)
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

-- ============================================================
-- Rail
-- ============================================================
--- The rail's rows: one per parameter, marked with the current
--- selection. Returned as data so the renderer only positions and
--- colours it.
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

-- ============================================================
-- Readout
-- ============================================================
--- The lines under the map: every parameter for whichever source is in
--- view — the selected channel if there is one, else the reactor-wide
--- scalars. `chan` is one entry of a column array (or nil).
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

-- ============================================================
-- Legend
-- ============================================================
--- Band names with their colours and the value each band starts at. A
--- map of coloured numbers with no key is decoration, not
--- instrumentation.
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
