-- ╔══════════════════════════════════════════════════════════════╗
-- ║  pic: from pixels to cells                                   ║
-- ║                                                              ║
-- ║  ▀ with the foreground for the top half and the background   ║
-- ║  for the bottom makes one cell into two square pixels of any ║
-- ║  two colours, which is the most an OpenComputers screen can  ║
-- ║  show a photograph with. So a picture shrinks to two pixel   ║
-- ║  rows a cell, then each pixel takes the nearest colour this  ║
-- ║  GPU has, with what that got wrong carried to its neighbours ║
-- ║  (Floyd-Steinberg). Tier 3 has 256 colours, tier 2 has 16,   ║
-- ║  and tier 1 has black and white, where only that carrying    ║
-- ║  keeps a picture a picture.                                  ║
-- ║                                                              ║
-- ║  One row at a time, so memory goes with the screen and not   ║
-- ║  with the PNG. Pure: bytes in, an image out.                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local O = require("pic.ocif")
local P = require("pic.png")

local M = {}

local floor = math.floor

--- OpenComputers' default tier 2 palette. A real GPU can say its own, and
--- init.lua asks; this is for a machine that cannot, and for the dev box.
M.T2_PALETTE = { 0xFFFFFF, 0xFFCC33, 0xCC66CC, 0x6699FF, 0xFFFF33, 0x33CC33,
                 0xFF6699, 0x333333, 0xCCCCCC, 0x336699, 0x9933CC, 0x333399,
                 0x663300, 0x336600, 0xFF3333, 0x000000 }

--- A function taking r, g, b to a palette index and the colour it really
--- is. depth: 8, 4 or 1 bits; palette: a list of 0xRRGGBB, for depth 4.
function M.quantizer(depth, palette)
  local to8 = O.to8
  if depth >= 8 then
    return function(r, g, b)
      local i = to8(r, g, b)
      local cr, cg, cb = O.rgb(O.PALETTE[i])
      return i, cr, cg, cb
    end
  end
  if depth <= 1 then
    local white = to8(255, 255, 255)
    return function(r, g, b)
      if r * 0.299 + g * 0.587 + b * 0.114 >= 128 then return white, 255, 255, 255 end
      return 0, 0, 0, 0
    end
  end
  local entries = {}
  for i, c in ipairs(palette or M.T2_PALETTE) do
    local r, g, b = O.rgb(c)
    entries[i] = { r, g, b, to8(r, g, b) }
  end
  return function(r, g, b)
    local best, bestD = entries[1], math.huge
    for i = 1, #entries do
      local e = entries[i]
      local d = (r - e[1]) ^ 2 + (g - e[2]) ^ 2 + (b - e[3]) ^ 2
      if d < bestD then best, bestD = e, d end
    end
    return best[4], best[1], best[2], best[3]
  end
end

--- The picture's size in pixels inside maxW x maxH cells: a cell is one
--- pixel wide and two tall. Never bigger than the picture.
function M.targetSize(sw, sh, maxW, maxH)
  local k = math.min(1, maxW / sw, (maxH * 2) / sh)
  local tw = math.max(1, floor(sw * k + 0.5))
  local th = math.max(1, floor(sh * k + 0.5))
  return tw, th
end

--- How many samples a pixel takes each way at most. Past this a picture
--- looks no better, and the time goes with the screen, not the source.
local SAMPLES = 3

--- Which source positions feed each target pixel: list[i] = { src, target }.
local function sampleMap(size, tsize)
  local list = {}
  for t = 1, tsize do
    local from = (t - 1) * size / tsize
    local n = math.min(SAMPLES, math.max(1, floor(size / tsize + 0.5)))
    for i = 0, n - 1 do
      local s = floor(from + (i + 0.5) * (size / tsize) / n) + 1
      list[#list + 1] = { math.min(size, s), t }
    end
  end
  return list
end

--- A PNG's bytes to an image. opts: maxW, maxH (cells), depth (8, 4, 1),
--- palette (for depth 4), dither (default on), progress(done, total).
function M.fromPNG(data, opts)
  opts = opts or {}
  local maxW, maxH = opts.maxW or 160, opts.maxH or 50
  local quant = M.quantizer(opts.depth or 8, opts.palette)
  local dither = opts.dither ~= false
  local xs, tw, th
  local rowsOf = {}                      -- source y -> target y
  local rows = {}

  local b = O.builder(1, 1)
  local UP, SP = string.char(b:symbol(O.UPPER)), string.char(b:symbol(" "))

  -- The target row being gathered, and the error carried into the next.
  local sr, sg, sb, sn = {}, {}, {}, {}
  local er, eg, eb = {}, {}, {}
  local top = nil
  local function clear()
    for x = 1, tw do sr[x], sg[x], sb[x], sn[x] = 0, 0, 0, 0 end
  end

  --- Quantise the gathered row, pair it up, and leave error for the next.
  local function flush(ty)
    local px = {}
    local nr, ng, nb = {}, {}, {}
    for x = 0, tw + 1 do nr[x], ng[x], nb[x] = 0, 0, 0 end
    local left = (ty % 2 == 1)           -- serpentine: no drift in one direction
    local from, to, step = 1, tw, 1
    if not left then from, to, step = tw, 1, -1 end
    for x = from, to, step do
      local n = sn[x]
      if n == 0 then n = 1 end
      local r, g, bl = sr[x] / n + (er[x] or 0), sg[x] / n + (eg[x] or 0), sb[x] / n + (eb[x] or 0)
      if r < 0 then r = 0 elseif r > 255 then r = 255 end
      if g < 0 then g = 0 elseif g > 255 then g = 255 end
      if bl < 0 then bl = 0 elseif bl > 255 then bl = 255 end
      local i, cr, cg, cb = quant(r, g, bl)
      px[x] = i
      if dither then
        local dr, dg, db = r - cr, g - cg, bl - cb
        local ahead = x + step
        if ahead >= 1 and ahead <= tw then
          -- 7/16 along the row, carried by hand into the next pixel's sum.
          local m = sn[ahead] > 0 and sn[ahead] or 1
          sr[ahead] = sr[ahead] + dr * 7 / 16 * m
          sg[ahead] = sg[ahead] + dg * 7 / 16 * m
          sb[ahead] = sb[ahead] + db * 7 / 16 * m
        end
        local behind = x - step
        nr[behind] = nr[behind] + dr * 3 / 16
        ng[behind] = ng[behind] + dg * 3 / 16
        nb[behind] = nb[behind] + db * 3 / 16
        nr[x] = nr[x] + dr * 5 / 16
        ng[x] = ng[x] + dg * 5 / 16
        nb[x] = nb[x] + db * 5 / 16
        nr[ahead] = nr[ahead] + dr / 16
        ng[ahead] = ng[ahead] + dg / 16
        nb[ahead] = nb[ahead] + db / 16
      end
    end
    er, eg, eb = nr, ng, nb
    if ty % 2 == 1 then
      top = px
    else
      rows[ty / 2] = O.pixelRow(top, px, tw, UP, SP)
      top = nil
    end
    clear()
  end

  local doneT = 0
  local ok, err = P.read(data, function(sw, sh)
    tw, th = M.targetSize(sw, sh, maxW, maxH)
    xs = sampleMap(sw, tw)
    for _, e in ipairs(sampleMap(sh, th)) do rowsOf[e[1]] = e[2] end
    clear()
    return rowsOf
  end, function(y, pixel)
    local ty = rowsOf[y]
    while doneT + 1 < ty do
      doneT = doneT + 1
      flush(doneT)
    end
    for i = 1, #xs do
      local e = xs[i]
      local r, g, bl, a = pixel(e[1])
      local t = e[2]
      -- Transparency over black, the dark behind every picture here.
      sr[t] = sr[t] + r * a / 255
      sg[t] = sg[t] + g * a / 255
      sb[t] = sb[t] + bl * a / 255
      sn[t] = sn[t] + 1
    end
  end, opts.progress)
  if not ok then return nil, err end
  while doneT < th do
    doneT = doneT + 1
    flush(doneT)
  end
  if th % 2 == 1 then
    -- An odd row at the bottom: its lower half is the dark behind it.
    local dark = {}
    for x = 1, tw do dark[x] = 0 end
    rows[(th + 1) / 2] = O.pixelRow(top, dark, tw, UP, SP)
  end
  return { w = tw, h = math.ceil(th / 2), syms = b.syms, rows = rows, lost = 0 }
end

return M
