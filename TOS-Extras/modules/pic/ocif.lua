-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  pic: the image model, and MineOS's .pic files               ║
-- ║                                                              ║
-- ║  An OpenComputers picture is not pixels. It is text cells,   ║
-- ║  each with a background, a foreground and one character, so  ║
-- ║  this module keeps exactly that: three byte strings a row,   ║
-- ║  three bytes a cell, because a table of 8,000 cells would    ║
-- ║  not fit on the machines that want to show one.              ║
-- ║                                                              ║
-- ║  .pic is MineOS's OCIF format, read from its Image.lua and   ║
-- ║  Color.lua (methods 5 to 8). Using it means every picture    ║
-- ║  MineOS users have made opens here, and what this writes     ║
-- ║  opens there. Pure: no fs, no GPU.                           ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

local byte, char, floor = string.byte, string.char, math.floor
local concat = table.concat

--- A file wider or taller than this is refused rather than allocated: the
--- biggest OpenComputers screen is 160x50, and a header is a stranger's.
M.MAX_CELLS = 256 * 256

-- ── The palette ────────────────────────────────────────────────────────
-- A cell's colours are one byte each. The 256 are OpenComputers' tier 3
-- palette: a 6x8x5 colour cube plus 16 greys, in ascending numeric order,
-- which is how MineOS numbers them.
local RL = { 0x00, 0x33, 0x66, 0x99, 0xCC, 0xFF }
local GL = { 0x00, 0x24, 0x49, 0x6D, 0x92, 0xB6, 0xDB, 0xFF }
local BL = { 0x00, 0x40, 0x80, 0xBF, 0xFF }

local PALETTE, INDEX = {}, {}      -- PALETTE[0..255] = 0xRRGGBB
do
  local all = {}
  for r = 1, 6 do for g = 1, 8 do for b = 1, 5 do
    all[#all + 1] = RL[r] * 65536 + GL[g] * 256 + BL[b]
  end end end
  for i = 1, 16 do all[#all + 1] = i * 0x0F0F0F end
  table.sort(all)
  for i, c in ipairs(all) do PALETTE[i - 1] = c; INDEX[c] = i - 1 end
end
M.PALETTE = PALETTE

--- Split 0xRRGGBB.
local function rgb(c)
  local b = c % 256
  local g = (c - b) / 256 % 256
  return floor(c / 65536), floor(g), b
end
M.rgb = rgb

--- The palette index nearest r, g, b. Works the cube out arithmetically
--- and only compares it with the nearest grey: this runs once a pixel, and
--- searching 256 entries there is what makes a conversion take minutes.
function M.to8(r, g, b)
  local cr = RL[floor(r * 5 / 255 + 0.5) + 1]
  local cg = GL[floor(g * 7 / 255 + 0.5) + 1]
  local cb = BL[floor(b * 4 / 255 + 0.5) + 1]
  local v = floor(((r + g + b) / 3) / 15 + 0.5)
  if v < 1 then v = 1 elseif v > 16 then v = 16 end
  local gv = v * 15
  local dc = (r - cr) ^ 2 + (g - cg) ^ 2 + (b - cb) ^ 2
  local dg = (r - gv) ^ 2 + (g - gv) ^ 2 + (b - gv) ^ 2
  if dg < dc then return INDEX[gv * 0x010101] end
  return INDEX[cr * 65536 + cg * 256 + cb]
end

--- Perceived brightness of a palette index, 0..255.
local LUMA = {}
for i = 0, 255 do
  local r, g, b = rgb(PALETTE[i])
  LUMA[i] = floor(r * 0.299 + g * 0.587 + b * 0.114)
end
M.LUMA = LUMA

-- ── The image ──────────────────────────────────────────────────────────
-- img = { w, h, syms = { [1] = "▀", ... },
--         rows = { [y] = { bg = bytes, fg = bytes, sym = bytes } } }
-- bg and fg hold palette indices; sym holds an index into syms.
M.UPPER, M.LOWER, M.FULL = "▀", "▄", "█"

--- Builds an image from cells set in any order.
--- One number a cell until finish(): OCIF stores cells by colour, not by
--- position, so nothing can be written out a row at a time.
function M.builder(w, h)
  local b = { w = w, h = h, syms = {}, index = {}, cells = {}, lost = 0 }
  --- The 1-based index for a character. A row holds one byte for it, so
  --- past 253 different ones the rest show as "?", and lost says how many.
  --- " " and "?" always get in: finish() needs one and this needs the
  --- other, and they are why the limit is not 255.
  function b:symbol(s)
    local i = self.index[s]
    if i then return i end
    if #self.syms >= 253 and s ~= " " and s ~= "?" then
      self.lost = self.lost + 1
      return self:symbol("?")
    end
    i = #self.syms + 1
    self.syms[i], self.index[s] = s, i
    return i
  end
  function b:set(x, y, bg, fg, sym)
    if x >= 1 and x <= w and y >= 1 and y <= h then
      self.cells[(y - 1) * w + x] = bg * 65536 + fg * 256 + sym
    end
  end
  function b:finish()
    local space = self:symbol(" ")
    local blank = space
    local rows, cells = {}, self.cells
    local bgs, fgs, ss = {}, {}, {}
    for y = 1, h do
      local base = (y - 1) * w
      for x = 1, w do
        local c = cells[base + x] or blank
        local sym = c % 256
        local rest = (c - sym) / 256
        local fg = rest % 256
        bgs[x], fgs[x], ss[x] = char(floor((rest - fg) / 256)), char(floor(fg)), char(floor(sym))
      end
      rows[y] = { bg = concat(bgs), fg = concat(fgs), sym = concat(ss) }
    end
    return { w = w, h = h, syms = self.syms, rows = rows, lost = self.lost }
  end
  return b
end

--- Build an image straight from pairs of pixel rows, as a converter makes
--- them: top[x] and bottom[x] are palette indices. No builder, so no table
--- of cells on a machine already short of memory.
--- A cell whose two halves match is a space: its foreground is then free,
--- which is what lets draw merge it into the run beside it.
function M.pixelRow(top, bottom, w, upper, space)
  local bgs, fgs, ss = {}, {}, {}
  for x = 1, w do
    local t, b = top[x], bottom[x]
    if t == b then
      bgs[x], fgs[x], ss[x] = char(b), char(b), space
    else
      bgs[x], fgs[x], ss[x] = char(b), char(t), upper
    end
  end
  return { bg = concat(bgs), fg = concat(fgs), sym = concat(ss) }
end

-- ── Reading OCIF ───────────────────────────────────────────────────────
local function reader(data, pos)
  local r = { pos = pos }
  function r:u8()
    local v = byte(data, self.pos)
    if not v then error("the file stops early", 0) end
    self.pos = self.pos + 1
    return v
  end
  function r:u16()
    local a = self:u8()
    return a * 256 + self:u8()
  end
  function r:char()
    local p, c = self.pos, self:u8()
    local n = (c < 0x80 and 0) or (c < 0xE0 and 1) or (c < 0xF0 and 2) or 3
    self.pos = p + n + 1
    if self.pos - 1 > #data then error("the file stops early", 0) end
    return data:sub(p, p + n)
  end
  return r
end

--- A colour seen through `alpha`/255 of transparency, over black: what is
--- behind a picture here is always the dark of the viewer. Cached, because
--- an OCIF names the same few pairs thousands of times.
local function faded(cache, index, alpha)
  if alpha == 0 then return index end
  local key = alpha * 256 + index
  local v = cache[key]
  if not v then
    local r, g, b = rgb(PALETTE[index])
    local k = 1 - alpha / 255
    v = M.to8(r * k, g * k, b * k)
    cache[key] = v
  end
  return v
end

local function decode5(r, b, w, h)
  local cache = {}
  for y = 1, h do
    for x = 1, w do
      local bg, fg, alpha = r:u8(), r:u8(), r:u8()
      local sym = r:char()
      if alpha == 255 then b:set(x, y, 0, 0, b:symbol(" "))
      else b:set(x, y, faded(cache, bg, alpha), faded(cache, fg, alpha), b:symbol(sym)) end
    end
  end
end

--- Methods 6, 7 and 8 are one layout: nested by alpha, character,
--- background, foreground, row. 7 stores each count less one, and 8 stores
--- positions less one as well.
local function decode678(r, b, count, pos)
  local cache = {}
  for _ = 1, r:u8() + count do
    local alpha = r:u8()
    for _ = 1, r:u16() + count do
      local sym = r:char()
      local si = alpha == 255 and b:symbol(" ") or b:symbol(sym)
      for _ = 1, r:u8() + count do
        local bg = r:u8()
        local fbg = alpha == 255 and 0 or faded(cache, bg, alpha)
        for _ = 1, r:u8() + count do
          local fg = r:u8()
          local ffg = alpha == 255 and 0 or faded(cache, fg, alpha)
          for _ = 1, r:u8() + count do
            local y = r:u8() + pos
            for _ = 1, r:u8() + count do b:set(r:u8() + pos, y, fbg, ffg, si) end
          end
        end
      end
    end
  end
end

--- Is this an OCIF file? Returns the method.
function M.method(data)
  if type(data) == "string" and data:sub(1, 4) == "OCIF" then return byte(data, 5) end
end

--- Width, height and method from the header alone.
function M.size(data)
  local method = M.method(data)
  if method == 5 then
    return byte(data, 6) * 256 + byte(data, 7), byte(data, 8) * 256 + byte(data, 9), method
  elseif method == 6 or method == 7 then
    return byte(data, 6), byte(data, 7), method
  elseif method == 8 then
    return byte(data, 6) + 1, byte(data, 7) + 1, method
  end
end

--- Decode a .pic. Returns the image, or nil and why.
function M.decode(data)
  local method = M.method(data)
  if not method then return nil, "not a .pic file" end
  if method < 5 or method > 8 then
    return nil, "OCIF method " .. tostring(method) .. " is not one this reads (5 to 8)"
  end
  if #data < 9 then return nil, "the file stops early" end
  local w, h = M.size(data)
  if not w or w < 1 or h < 1 or w * h > M.MAX_CELLS then
    return nil, string.format("a %sx%s picture is not one this can hold", tostring(w), tostring(h))
  end
  local b = M.builder(w, h)
  local r = reader(data, method == 5 and 10 or 8)
  local ok, err = pcall(function()
    if method == 5 then decode5(r, b, w, h)
    else decode678(r, b, method == 6 and 0 or 1, method == 8 and 1 or 0) end
  end)
  if not ok then return nil, tostring(err) end
  return b:finish()
end

-- ── Writing OCIF ───────────────────────────────────────────────────────
local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

--- A .pic of `img`, as method 8, the one MineOS itself writes. Method 8
--- cannot say more than 256 of anything, so anything wider or taller goes
--- out as method 5, which is bigger and has no such limit. The order is
--- sorted, so one picture always writes the same bytes.
function M.encode(img)
  local w, h = img.w, img.h
  local out = { "OCIF" }
  local function put(...) out[#out + 1] = char(...) end
  if w > 256 or h > 256 then
    put(5, floor(w / 256), w % 256, floor(h / 256), h % 256)
    for y = 1, h do
      local row = img.rows[y]
      for x = 1, w do
        put(byte(row.bg, x), byte(row.fg, x), 0)
        out[#out + 1] = img.syms[byte(row.sym, x)]
      end
    end
    return concat(out)
  end
  put(8, w - 1, h - 1)
  local tree = {}                      -- tree[sym][bg][fg][y] = { x, ... }
  for y = 1, h do
    local row = img.rows[y]
    for x = 1, w do
      local s, bg, fg = byte(row.sym, x), byte(row.bg, x), byte(row.fg, x)
      local a = tree[s]; if not a then a = {}; tree[s] = a end
      local c = a[bg]; if not c then c = {}; a[bg] = c end
      local d = c[fg]; if not d then d = {}; c[fg] = d end
      local e = d[y]; if not e then e = {}; d[y] = e end
      e[#e + 1] = x
    end
  end
  local syms = sortedKeys(tree)
  put(0, 0, floor((#syms - 1) / 256), (#syms - 1) % 256)   -- one alpha: opaque
  for _, s in ipairs(syms) do
    out[#out + 1] = img.syms[s]
    local bgs = sortedKeys(tree[s])
    put(#bgs - 1)
    for _, bg in ipairs(bgs) do
      local fgs = sortedKeys(tree[s][bg])
      put(bg, #fgs - 1)
      for _, fg in ipairs(fgs) do
        local ys = sortedKeys(tree[s][bg][fg])
        put(fg, #ys - 1)
        for _, y in ipairs(ys) do
          local xs = tree[s][bg][fg][y]
          put(y - 1, #xs - 1)
          for i = 1, #xs do put(xs[i] - 1) end
        end
      end
    end
  end
  return concat(out)
end

-- ── Fitting a picture to a screen ──────────────────────────────────────
--- Is every character a block? Then a cell is two pixels, and the picture
--- can be scaled by pixel; otherwise only by whole cells.
local function isBlocks(img)
  for _, s in ipairs(img.syms) do
    if s ~= M.UPPER and s ~= M.LOWER and s ~= M.FULL and s ~= " " then return false end
  end
  return true
end

--- The largest size inside maxW x maxH cells that keeps the shape. Cells
--- are twice as tall as wide whichever way a picture was made, so one
--- proportion serves both.
function M.fit(w, h, maxW, maxH)
  local k = math.min(maxW / w, maxH / h)
  if k >= 1 then return w, h end
  return math.max(1, floor(w * k)), math.max(1, floor(h * k))
end

--- A smaller copy of `img`, nearest-neighbour. Done at viewing time, so it
--- never loses more than the screen in front of it needs.
function M.scale(img, w, h)
  local sw, sh = img.w, img.h
  local rows = {}
  local xmap = {}
  for x = 1, w do xmap[x] = floor((x - 0.5) * sw / w) + 1 end
  if isBlocks(img) then
    local upper, space
    local kind = {}                    -- sym index -> which half is fg
    local b = M.builder(1, 1)          -- a table of two symbols, no more
    upper, space = b:symbol(M.UPPER), b:symbol(" ")
    for i, s in ipairs(img.syms) do kind[i] = s end
    local UP, SP = char(upper), char(space)
    --- One row of pixels: py counts half-cells from the top.
    local function pixels(py, out)
      local half = py % 2                 -- 1 = the cell's top half
      local row = img.rows[floor((py + 1) / 2)]
      for x = 1, w do
        local sx = xmap[x]
        local s = kind[byte(row.sym, sx)]
        local useFg = s == M.FULL or (s == M.UPPER and half == 1) or (s == M.LOWER and half == 0)
        out[x] = byte(useFg and row.fg or row.bg, sx)
      end
    end
    local top, bottom = {}, {}
    for y = 1, h do
      pixels(floor((y - 0.75) * sh / h * 2) + 1, top)
      pixels(floor((y - 0.25) * sh / h * 2) + 1, bottom)
      rows[y] = M.pixelRow(top, bottom, w, UP, SP)
    end
    return { w = w, h = h, syms = b.syms, rows = rows, lost = img.lost }
  end
  local bgs, fgs, ss = {}, {}, {}
  for y = 1, h do
    local row = img.rows[floor((y - 0.5) * sh / h) + 1]
    for x = 1, w do
      local sx = xmap[x]
      bgs[x], fgs[x], ss[x] = row.bg:sub(sx, sx), row.fg:sub(sx, sx), row.sym:sub(sx, sx)
    end
    rows[y] = { bg = concat(bgs), fg = concat(fgs), sym = concat(ss) }
  end
  return { w = w, h = h, syms = img.syms, rows = rows, lost = img.lost }
end

return M
