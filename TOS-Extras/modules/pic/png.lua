-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  pic: reading a PNG, in plain Lua                            ║
-- ║                                                              ║
-- ║  MineOS sends a picture to a web service to be converted.    ║
-- ║  This does it on the machine, so a PNG off the internet card ║
-- ║  shows with nothing else in the loop: inflate, the five      ║
-- ║  filters and every colour type, one row at a time. Only two  ║
-- ║  rows and the 32 KB window are ever held, so the image's     ║
-- ║  size costs time rather than memory.                         ║
-- ║                                                              ║
-- ║  No bit operators, no //: this has to parse on Lua 5.2 too.  ║
-- ║  Pure: bytes in, rows out.                                   ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

local byte, floor = string.byte, math.floor

--- The biggest side accepted, because a header is a stranger's and a row
--- costs memory.
M.MAX_SIDE = 8192

-- ── Huffman tables ─────────────────────────────────────────────────────
-- A table is the count of codes of each length and the symbols in code
-- order; decoding walks the lengths. That is RFC 1951's canonical form.
local function huffman(lengths, n)
  local count, offs, symbol = {}, {}, {}
  for len = 0, 15 do count[len] = 0 end
  for i = 0, n - 1 do count[lengths[i]] = count[lengths[i]] + 1 end
  offs[1] = 0
  for len = 1, 14 do offs[len + 1] = offs[len] + count[len] end
  for i = 0, n - 1 do
    local l = lengths[i]
    if l ~= 0 then
      symbol[offs[l]] = i
      offs[l] = offs[l] + 1
    end
  end
  return { count = count, symbol = symbol }
end

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                   35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                    8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                     7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local fixedLit, fixedDist

--- Inflate raw deflate data from `data` at `pos`, handing every byte to
--- sink(b). sink returns true when it has all it wants, which ends this
--- however much the stream claims is left: a small header cannot be made
--- to unpack forever.
local function inflate(data, pos, sink)
  local cur, left = 0, 0                 -- the byte being read, bits left

  local function bits(n)
    local v, mul = 0, 1
    for _ = 1, n do
      if left == 0 then
        cur = byte(data, pos)
        if not cur then error("the file stops early", 0) end
        pos = pos + 1
        left = 8
      end
      local b = cur % 2
      cur = (cur - b) / 2
      left = left - 1
      v = v + b * mul
      mul = mul * 2
    end
    return v
  end

  local function decode(h)
    local code, first, index = 0, 0, 0
    local count, symbol = h.count, h.symbol
    for len = 1, 15 do
      if left == 0 then
        cur = byte(data, pos)
        if not cur then error("the file stops early", 0) end
        pos = pos + 1
        left = 8
      end
      local b = cur % 2
      cur = (cur - b) / 2
      left = left - 1
      code = code + b
      local c = count[len]
      if code - c < first then return symbol[index + (code - first)] end
      index = index + c
      first = (first + c) * 2
      code = code * 2
    end
    error("the compressed data is damaged", 0)
  end

  -- The window: the last 32 KB out, as a ring. It only grows as far as the
  -- output has, so a small picture never pays for all of it.
  local win, wpos, total = {}, 0, 0
  local function emit(b)
    win[wpos] = b
    wpos = (wpos + 1) % 32768
    total = total + 1
    return sink(b)
  end

  local function codes(lit, dist)
    while true do
      local sym = decode(lit)
      if sym < 256 then
        if emit(sym) then return true end
      elseif sym == 256 then
        return false
      else
        sym = sym - 256
        local base = LEN_BASE[sym]
        if not base then error("the compressed data is damaged", 0) end
        local len = base + bits(LEN_EXTRA[sym])
        local ds = decode(dist) + 1
        local dbase = DIST_BASE[ds]
        if not dbase then error("the compressed data is damaged", 0) end
        local d = dbase + bits(DIST_EXTRA[ds])
        if d > total then error("the compressed data is damaged", 0) end
        for _ = 1, len do
          if emit(win[(wpos - d) % 32768]) then return true end
        end
      end
    end
  end

  while true do
    local last = bits(1)
    local kind = bits(2)
    if kind == 0 then
      left = 0
      local a, b = byte(data, pos, pos + 1)
      if not b then error("the file stops early", 0) end
      local len = a + b * 256
      pos = pos + 4
      for i = 0, len - 1 do
        local v = byte(data, pos + i)
        if not v then error("the file stops early", 0) end
        if emit(v) then return end
      end
      pos = pos + len
    elseif kind == 1 then
      if not fixedLit then
        local l = {}
        for i = 0, 143 do l[i] = 8 end
        for i = 144, 255 do l[i] = 9 end
        for i = 256, 279 do l[i] = 7 end
        for i = 280, 287 do l[i] = 8 end
        fixedLit = huffman(l, 288)
        local d = {}
        for i = 0, 29 do d[i] = 5 end
        fixedDist = huffman(d, 30)
      end
      if codes(fixedLit, fixedDist) then return end
    elseif kind == 2 then
      local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
      local lengths = {}
      for i = 0, 18 do lengths[i] = 0 end
      for i = 1, ncode do lengths[CODE_ORDER[i]] = bits(3) end
      local cl = huffman(lengths, 19)
      local all, i = {}, 0
      while i < nlen + ndist do
        local sym = decode(cl)
        if sym < 16 then
          all[i] = sym
          i = i + 1
        else
          local prev, rep = 0, 0
          if sym == 16 then
            if i == 0 then error("the compressed data is damaged", 0) end
            prev = all[i - 1]
            rep = 3 + bits(2)
          elseif sym == 17 then rep = 3 + bits(3)
          else rep = 11 + bits(7) end
          if i + rep > nlen + ndist then error("the compressed data is damaged", 0) end
          for _ = 1, rep do all[i] = prev; i = i + 1 end
        end
      end
      local ll, dl = {}, {}
      for j = 0, nlen - 1 do ll[j] = all[j] end
      for j = 0, ndist - 1 do dl[j] = all[nlen + j] end
      if codes(huffman(ll, nlen), huffman(dl, ndist)) then return end
    else
      error("the compressed data is damaged", 0)
    end
    if last == 1 then return end
  end
end
M.inflate = inflate

-- ── The file ───────────────────────────────────────────────────────────
local function u32(s, p)
  local a, b, c, d = byte(s, p, p + 3)
  if not d then error("the file stops early", 0) end
  return a * 16777216 + b * 65536 + c * 256 + d
end

--- Is this a PNG?
function M.is(data)
  return type(data) == "string" and data:sub(1, 8) == "\137PNG\r\n\26\n"
end

--- Width and height from the header alone.
function M.size(data)
  if M.is(data) and #data >= 24 then return u32(data, 17), u32(data, 21) end
end

local CHANNELS = { [0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4 }

local function paeth(a, b, c)
  local p = a + b - c
  local pa, pb, pc = p - a, p - b, p - c
  if pa < 0 then pa = -pa end
  if pb < 0 then pb = -pb end
  if pc < 0 then pc = -pc end
  if pa <= pb and pa <= pc then return a end
  if pb <= pc then return b end
  return c
end

--- Read one row's packed samples into a pixel getter for this colour type.
local function pixelReader(ctype, depth, palette, trans, row)
  local BPP = CHANNELS[ctype]
  if depth < 8 then
    -- Packed samples, leftmost pixel in the high bits. Greyscale scales up
    -- to 0..255; a palette index does not.
    local per = 8 / depth
    local mask = 2 ^ depth
    local top = mask - 1
    local function sample(x)
      local i = x - 1
      local rem = i % per
      local v = row[(i - rem) / per + 1]
      v = floor(v / 2 ^ ((per - 1 - rem) * depth)) % mask
      return v
    end
    if ctype == 3 then
      return function(x)
        local e = palette[sample(x)]
        if not e then return 0, 0, 0, 255 end
        return e[1], e[2], e[3], e[4]
      end
    end
    return function(x)
      local s = sample(x)
      if trans and trans.grey == s then return 0, 0, 0, 0 end
      local v = floor(s * 255 / top)
      return v, v, v, 255
    end
  end
  local step = depth == 16 and 2 or 1
  local w = BPP * step
  if ctype == 3 then
    return function(x)
      local e = palette[row[x]]
      if not e then return 0, 0, 0, 255 end
      return e[1], e[2], e[3], e[4]
    end
  elseif ctype == 0 then
    return function(x)
      local v = row[(x - 1) * w + 1]
      if trans and trans.grey == v then return 0, 0, 0, 0 end
      return v, v, v, 255
    end
  elseif ctype == 4 then
    return function(x)
      local i = (x - 1) * w
      local v = row[i + 1]
      return v, v, v, row[i + step + 1]
    end
  elseif ctype == 2 then
    return function(x)
      local i = (x - 1) * w
      local r, g, b = row[i + 1], row[i + step + 1], row[i + 2 * step + 1]
      if trans and trans.r == r and trans.g == g and trans.b == b then return 0, 0, 0, 0 end
      return r, g, b, 255
    end
  end
  return function(x)
    local i = (x - 1) * w
    return row[i + 1], row[i + step + 1], row[i + 2 * step + 1], row[i + 3 * step + 1]
  end
end

--- Decode a PNG. onHeader(w, h) is called first and may return a list of
--- the rows it wants as a set, or nil for all; onRow(y, pixel) is called
--- for each one, and pixel(x) gives r, g, b, a in 0..255 until it returns.
--- progress(y, height), if given, runs after every row wanted or not: on a
--- real machine it is what keeps a long unpack from being killed for not
--- yielding. Returns true, or nil and why.
function M.read(data, onHeader, onRow, progress)
  if not M.is(data) then return nil, "not a PNG file" end
  local width, height, depth, ctype
  local palette, trans = nil, nil
  local idat = {}
  local pos = 9
  local ok, err = pcall(function()
    while true do
      local len = u32(data, pos)
      local name = data:sub(pos + 4, pos + 7)
      local body = pos + 8
      if body + len - 1 > #data then error("the file stops early", 0) end
      if name == "IHDR" then
        width, height = u32(data, body), u32(data, body + 4)
        local a, b, c, d, e = byte(data, body + 8, body + 12)
        depth, ctype = a, b
        if not e or c ~= 0 or d ~= 0 then error("this PNG uses a method nothing writes", 0) end
        if e ~= 0 then error("interlaced PNGs are not supported: save it without interlacing", 0) end
        if not CHANNELS[ctype] or width < 1 or height < 1
           or width > M.MAX_SIDE or height > M.MAX_SIDE then
          error(string.format("a %dx%d PNG of colour type %d is not one this can read",
            width, height, ctype), 0)
        end
      elseif name == "PLTE" then
        palette = {}
        for i = 0, floor(len / 3) - 1 do
          local r, g, b = byte(data, body + i * 3, body + i * 3 + 2)
          palette[i] = { r, g, b, 255 }
        end
      elseif name == "tRNS" then
        if ctype == 3 and palette then
          for i = 0, len - 1 do
            if palette[i] then palette[i][4] = byte(data, body + i) end
          end
        elseif ctype == 0 and len >= 2 then
          trans = { grey = depth == 16 and byte(data, body) or byte(data, body + 1) }
        elseif ctype == 2 and len >= 6 then
          local o = depth == 16 and 0 or 1
          trans = { r = byte(data, body + o), g = byte(data, body + 2 + o), b = byte(data, body + 4 + o) }
        end
      elseif name == "IDAT" then
        idat[#idat + 1] = data:sub(body, body + len - 1)
      elseif name == "IEND" then
        return
      end
      pos = body + len + 4
    end
  end)
  if not ok then return nil, tostring(err) end
  if not width then return nil, "this PNG has no header" end
  if ctype == 3 and not palette then return nil, "this PNG has no palette" end
  if #idat == 0 then return nil, "this PNG has no picture in it" end

  local bpp = math.max(1, floor(CHANNELS[ctype] * depth / 8))
  local stride = math.ceil(width * CHANNELS[ctype] * depth / 8)
  local want = onHeader and onHeader(width, height)
  local z = table.concat(idat)
  idat = nil
  if (byte(z, 1) or 0) % 16 ~= 8 then return nil, "this PNG is not compressed the usual way" end

  local cur, prev = {}, {}
  for i = 1, stride do prev[i] = 0 end
  local pixel = pixelReader(ctype, depth, palette, trans, cur)
  local y, col, filter = 1, 0, nil

  local function sink(v)
    if not filter then filter = v; return false end
    col = col + 1
    local a = col > bpp and cur[col - bpp] or 0
    local b = prev[col]
    if filter == 1 then v = (v + a) % 256
    elseif filter == 2 then v = (v + b) % 256
    elseif filter == 3 then v = (v + floor((a + b) / 2)) % 256
    elseif filter == 4 then
      v = (v + paeth(a, b, col > bpp and prev[col - bpp] or 0)) % 256
    elseif filter ~= 0 then
      error("the compressed data is damaged", 0)
    end
    cur[col] = v
    if col == stride then
      if not want or want[y] then onRow(y, pixel) end
      if progress then progress(y, height) end
      -- `pixel` reads `cur`, so the rows swap by copying, not by name.
      for i = 1, stride do prev[i] = cur[i] end
      y, col, filter = y + 1, 0, nil
      if y > height then return true end
    end
    return false
  end

  local okI, errI = pcall(inflate, z, 3, sink)
  if not okI then
    if type(errI) == "string" and errI:find("not enough memory", 1, true) then
      return nil, "not enough memory to unpack this PNG"
    end
    return nil, tostring(errI)
  end
  if y <= height then return nil, "the picture ends early" end
  return true
end

return M
