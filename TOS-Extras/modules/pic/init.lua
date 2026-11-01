-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: pic — pictures on a text screen                 ║
-- ║                                                              ║
-- ║  Shows a MineOS .pic or a PNG, from a disk or straight off   ║
-- ║  the internet card, on any GPU: 256 colours on tier 3, 16 on ║
-- ║  tier 2, and dithered black and white on tier 1. `pic        ║
-- ║  convert` turns a PNG into a .pic.                           ║
-- ║                                                              ║
-- ║  The formats and the dithering live in ocif.lua, png.lua and ║
-- ║  convert.lua, all pure; this file is painting, the command   ║
-- ║  line and the keys.                                          ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local O = require("pic.ocif")
local P = require("pic.png")
local C = require("pic.convert")

-- The sandbox's `internet` global, given to a package that holds the
-- capability. require("internet") is a different thing with no get.
local internet = internet

local V = {}   -- exported for test_pic.lua

local byte, floor = string.byte, math.floor
local WHITE, BLACK = 255, 0
local MAX_FETCH = 2 * 1024 * 1024

-- ── Keys ───────────────────────────────────────────────────────────────
local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function isQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return ch == 17 or code == 68 or code == 1
end
local function quitLabel()
  if KEYS and KEYS.label then
    local l = KEYS.label("quit")
    if l ~= "" then return l end
  end
  return "^Q"
end
local K = { UP = 200, DOWN = 208, LEFT = 203, RIGHT = 205, PGUP = 201, PGDN = 209, HOME = 199 }

-- ── Painting ───────────────────────────────────────────────────────────
-- A 4x4 ordered dither: one half-cell's brightness against the threshold
-- for where it sits. Only for a .pic on a tier 1 screen: a PNG arrives here
-- already black and white, and 0 and 255 pass any threshold unchanged.
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local function lit(x, py, luma)
  return luma >= (BAYER[(py % 4) * 4 + (x % 4) + 1] + 0.5) * 16
end

--- A cell for a one-bit screen: bg, fg, text. Blocks are dithered by the
--- half; anything else stays legible by keeping its two colours opposite.
local function monoCell(bg, fg, text, x, y)
  local L = O.LUMA
  if text == O.UPPER or text == O.LOWER or text == O.FULL or text == " " then
    local top, bot = bg, bg
    if text == O.FULL then top, bot = fg, fg
    elseif text == O.UPPER then top = fg
    elseif text == O.LOWER then bot = fg end
    local t, b = lit(x, y * 2, L[top]), lit(x, y * 2 + 1, L[bot])
    if t and b then return WHITE, WHITE, " " end
    if t then return BLACK, WHITE, O.UPPER end
    if b then return BLACK, WHITE, O.LOWER end
    return BLACK, BLACK, " "
  end
  if L[bg] >= 128 then return WHITE, BLACK, text end
  return BLACK, WHITE, text
end
V.monoCell = monoCell

--- Paint w x h cells of `img` from (sx, sy) to screen (dx, dy).
--- Each row is split into runs of one colour pair, and the runs are sent
--- sorted by colour: a colour change costs the GPU budget as a set does,
--- and a photograph on a tier 3 screen is 8,000 of them. A space's
--- foreground never shows, so it joins whatever run it lands in.
function V.paint(gpu, img, sx, sy, dx, dy, w, h, mono, pump)
  local pal, syms = O.PALETTE, img.syms
  local curFg, curBg
  for yy = 0, h - 1 do
    local row = img.rows[sy + yy]
    if row then
      local rbg, rfg, rsym = row.bg, row.fg, row.sym
      local function cell(off)
        local i = sx + off
        local s = byte(rsym, i)
        if not s then return nil end
        local bg, fg, text = byte(rbg, i), byte(rfg, i), syms[s]
        if mono then return monoCell(bg, fg, text, i, sy + yy) end
        return bg, fg, text
      end
      local groups, keys = {}, {}
      local x = 0
      while x < w do
        local bg, fg, text = cell(x)
        if not bg then break end
        local start, parts = x, { text }
        local runFg = text ~= " " and fg or nil
        x = x + 1
        while x < w do
          local b2, f2, t2 = cell(x)
          if b2 ~= bg then break end
          if t2 ~= " " then
            if runFg == nil then runFg = f2 elseif f2 ~= runFg then break end
          end
          parts[#parts + 1] = t2
          x = x + 1
        end
        -- 256 means "any foreground".
        local key = bg * 512 + (runFg or 256)
        local g = groups[key]
        if not g then g = {}; groups[key] = g; keys[#keys + 1] = key end
        g[#g + 1] = start
        g[#g + 1] = table.concat(parts)
      end
      table.sort(keys)
      for _, key in ipairs(keys) do
        local fg = key % 512
        local bg = floor((key - fg) / 512)
        if bg ~= curBg then gpu.setBackground(pal[bg]); curBg = bg end
        if fg ~= 256 and fg ~= curFg then gpu.setForeground(pal[fg]); curFg = fg end
        local g = groups[key]
        for i = 1, #g, 2 do gpu.set(dx + g[i], dy + yy, g[i + 1]) end
      end
    end
    if pump then pump() end
  end
end

-- ── Getting a picture ──────────────────────────────────────────────────
--- Bytes from a path or a URL.
local function fetch(src)
  if src:match("^https?://") then
    if type(internet) ~= "table" or type(internet.get) ~= "function" then
      return nil, "no internet here: this needs an internet card"
    end
    local body, err = internet.get(src, { maxBytes = MAX_FETCH })
    if not body then return nil, tostring(err) end
    return body
  end
  if not (fs and fs.exists and fs.exists(src)) then return nil, "no such file: " .. src end
  local ok, data = pcall(fs.readFile, src)
  if not ok or type(data) ~= "string" then return nil, "cannot read " .. src .. ": " .. tostring(data) end
  return data
end

--- A picture from its bytes. opts as for convert.fromPNG.
function V.decode(data, opts)
  if O.method(data) then return O.decode(data) end
  if P.is(data) then return C.fromPNG(data, opts) end
  return nil, "not a picture this can read (.pic or .png)"
end

--- Pictures in a directory, sorted, or nil if `src` is not one.
local function picturesIn(src)
  if src:match("^https?://") or not (fs and fs.isDirectory) then return nil end
  local okD, isDir = pcall(fs.isDirectory, src)
  if not okD or not isDir then return nil end
  local out = {}
  for _, name in ipairs(fs.list(src) or {}) do
    local lower = name:lower()
    if lower:match("%.pic$") or lower:match("%.png$") then
      out[#out + 1] = (src:gsub("/+$", "")) .. "/" .. name
    end
  end
  table.sort(out)
  return out
end

-- ── The screen ─────────────────────────────────────────────────────────
local function screen()
  local addr = component.list and component.list("gpu")()
  if not addr then return nil, "no GPU" end
  local okG, gpu = pcall(component.proxy, addr)
  if not okG or not gpu then return nil, "cannot open the GPU" end
  local Wd, Ht = gpu.getResolution()
  if not Wd or Wd < 20 or Ht < 5 then return nil, "this screen is too small" end
  local okD, depth = pcall(gpu.getDepth)
  depth = (okD and type(depth) == "number") and depth or 1
  local S = { gpu = gpu, W = Wd, H = Ht, depth = depth, mono = depth <= 1 }
  -- A tier 2 GPU's 16 colours can be anything; dither to the real ones.
  if depth == 4 and gpu.getPaletteColor then
    local list = {}
    for i = 0, 15 do
      local okP, c = pcall(gpu.getPaletteColor, i)
      if okP and type(c) == "number" then list[#list + 1] = c end
    end
    if #list == 16 then S.palette = list end
  end
  return S
end

local function baseName(s)
  return s:match("([^/]+)/*$") or s
end

--! A long unpack with no yield gets the machine killed, so the work stops
--! to let the world turn about once a second. Keys pressed meanwhile are
--! lost, which is why the viewer's keys all act on what is on screen.
local function pumper()
  local last = computer.uptime()
  return function()
    local now = computer.uptime()
    if now - last >= 1 then computer.pullSignal(0); last = now end
  end
end

local function pullKey()
  local e = { computer.pullSignal() }
  if e[1] == "key_down" then return e[3], e[4], e[1] end
  if e[1] == "interrupted" then return 17, nil, e[1] end
  return nil, nil, e[1]
end

local function ui(o, list, first)
  local S, why = screen()
  if not S then o("pic: " .. why, 0xFF6600); return end
  local gpu, Wd, Ht = S.gpu, S.W, S.H
  local index = first or 1
  local bar = true             -- the bottom row belongs to the bar
  local native = false         -- off: fitted to the screen; on: full size, panned
  local full, shown, err
  local px, py = 1, 1
  local pump = pumper()

  local function barRow(text)
    gpu.setBackground(0xFFFFFF)
    gpu.setForeground(0x000000)
    gpu.fill(1, Ht, Wd, 1, " ")
    gpu.set(2, Ht, text:sub(1, Wd - 2))
  end
  local function area() return Wd, bar and Ht - 1 or Ht end

  local function load()
    local aw, ah = area()
    local name = baseName(list[index])
    barRow("Reading " .. name)
    local data, e = fetch(list[index])
    full, shown, err = nil, nil, e
    if data then
      local tall = native and 2 or 1
      local last = -1
      full, e = V.decode(data, { maxW = aw * tall, maxH = ah * tall, depth = S.depth,
        palette = S.palette, progress = function(y, total)
          local pct = floor(y * 100 / total)
          if pct ~= last and pct % 5 == 0 then
            last = pct
            barRow(string.format("Reading %s  %d%%", name, pct))
          end
          pump()
        end })
      err = e
    end
    if full and not native then
      local fw, fh = O.fit(full.w, full.h, aw, ah)
      shown = (fw == full.w and fh == full.h) and full or O.scale(full, fw, fh)
    else
      shown = full
    end
    px, py = 1, 1
  end

  local function draw()
    local aw, ah = area()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, Wd, Ht, " ")
    local name = baseName(list[index])
    if not shown then
      gpu.set(2, 2, ("Cannot show " .. name):sub(1, Wd - 2))
      gpu.set(2, 3, tostring(err):sub(1, Wd - 2))
    else
      local w, h = math.min(shown.w, aw), math.min(shown.h, ah)
      local dx = math.max(0, floor((aw - shown.w) / 2))
      local dy = math.max(0, floor((ah - shown.h) / 2))
      V.paint(gpu, shown, px, py, dx + 1, dy + 1, w, h, S.mono, pump)
    end
    if bar then
      local parts = { name }
      if shown then parts[#parts + 1] = shown.w .. "x" .. shown.h end
      if #list > 1 then parts[#parts + 1] = index .. "/" .. #list end
      parts[#parts + 1] = (native and "F Fit" or "F Full") .. " · B Bar"
        .. (#list > 1 and " · N Next · P Prev" or "") .. " · " .. quitLabel() .. " Quit"
      barRow(table.concat(parts, "  "))
    end
  end

  local function pan(dx, dy)
    if not shown then return end
    local aw, ah = area()
    local nx = math.max(1, math.min(px + dx, shown.w - aw + 1))
    local ny = math.max(1, math.min(py + dy, shown.h - ah + 1))
    if nx ~= px or ny ~= py then px, py = nx, ny; draw() end
  end

  load()
  draw()
  while true do
    local ch, code, ev = pullKey()
    if ev == "tos_focus" then draw()
    elseif ch or code then
      local c = ch and ch > 0 and string.char(ch):lower() or ""
      local aw, ah = area()
      if isQuit(ch, code) or c == "q" then break
      elseif code == K.LEFT then pan(-math.max(1, floor(aw / 4)), 0)
      elseif code == K.RIGHT then pan(math.max(1, floor(aw / 4)), 0)
      elseif code == K.UP then pan(0, -math.max(1, floor(ah / 4)))
      elseif code == K.DOWN then pan(0, math.max(1, floor(ah / 4)))
      elseif code == K.HOME then pan(-(shown and shown.w or 0), -(shown and shown.h or 0))
      elseif c == "f" then native = not native; load(); draw()
      elseif c == "b" then bar = not bar; load(); draw()
      elseif (c == "n" or code == K.PGDN) and #list > 1 then
        index = index % #list + 1; load(); draw()
      elseif (c == "p" or code == K.PGUP) and #list > 1 then
        index = (index - 2) % #list + 1; load(); draw()
      end
    end
  end
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, Wd, Ht, " ")
end

-- ── Command line ───────────────────────────────────────────────────────
local function help(o)
  o("pic — pictures on a text screen", 0xFFFF55)
  o("  pic <file>                  show a .pic or a .png", 0xFFFFFF)
  o("  pic <directory>             show the pictures in it, N and P to move", 0xFFFFFF)
  o("  pic <http://...>            fetch one and show it", 0xFFFFFF)
  o("  pic info <file>             its format and size", 0xFFFFFF)
  o("  pic convert <in.png> <out.pic> [--width N] [--height N] [--tier 1|2|3] [--no-dither]", 0xFFFFFF)
  o("  Keys: F full size or fit, arrows pan, B bar, " .. quitLabel() .. " quit", 0xAAAAAA)
end

local function cliInfo(args, o)
  local src = args[2]
  if not src then o("Which file?", 0xFF5555); return end
  local data, err = fetch(src)
  if not data then o(err, 0xFF5555); return end
  if O.method(data) then
    local w, h, method = O.size(data)
    o(string.format("%s: MineOS .pic (OCIF %d), %sx%s cells, %d bytes", baseName(src), method,
      tostring(w), tostring(h), #data), 0xFFFFFF)
  elseif P.is(data) then
    local w, h = P.size(data)
    o(string.format("%s: PNG, %sx%s pixels, %d bytes", baseName(src), tostring(w), tostring(h), #data), 0xFFFFFF)
  else
    o("Not a picture this can read (.pic or .png).", 0xFF5555)
  end
end

--- --name value and --flag out of a list of words.
function V.parseConvert(args)
  local opts = { maxW = 160, maxH = 50, depth = 8, dither = true }
  local pos = {}
  local i = 2
  while i <= #args do
    local a = args[i]
    if a == "--width" or a == "--height" or a == "--tier" then
      local n = tonumber(args[i + 1])
      if not n or n < 1 then return nil, a .. " needs a number" end
      if a == "--width" then opts.maxW = n
      elseif a == "--height" then opts.maxH = n
      elseif n <= 1 then opts.depth = 1
      elseif n == 2 then opts.depth = 4
      else opts.depth = 8 end
      i = i + 2
    elseif a == "--no-dither" then
      opts.dither = false
      i = i + 1
    elseif a:sub(1, 2) == "--" then
      return nil, "unknown option " .. a
    else
      pos[#pos + 1] = a
      i = i + 1
    end
  end
  if #pos ~= 2 then return nil, "pic convert <in.png> <out.pic>" end
  return opts, pos[1], pos[2]
end

local function cliConvert(args, o)
  local opts, src, dest = V.parseConvert(args)
  if not opts then o(src, 0xFF5555); return end
  local data, err = fetch(src)
  if not data then o(err, 0xFF5555); return end
  if not P.is(data) then o(baseName(src) .. " is not a PNG.", 0xFF5555); return end
  local pump = pumper()
  opts.progress = function() pump() end
  local img
  img, err = C.fromPNG(data, opts)
  if not img then o("Cannot convert: " .. tostring(err), 0xFF5555); return end
  local body = O.encode(img)
  if not (fs and fs.writeFile) then o("Nothing here can write a file.", 0xFF5555); return end
  -- A refusal is a return of false and a reason, not an error.
  local okW, wErr, why = pcall(fs.writeFile, dest, body)
  if not okW or wErr == false or wErr == nil then
    o("Not saved: " .. tostring(okW and (why or "the write was refused") or wErr), 0xFF5555)
    return
  end
  o(string.format("Wrote %s: %dx%d cells, %d bytes.", dest, img.w, img.h, #body), 0x55FF55)
end

local function picCmd(args, o)
  args = args or {}
  o = o or print
  local a = args[1]
  if not a or a == "help" or a == "--help" or a == "-h" then help(o); return end
  if a == "info" then cliInfo(args, o); return end
  if a == "convert" then cliConvert(args, o); return end
  local list = picturesIn(a)
  if list then
    if #list == 0 then o("No .pic or .png files in " .. a, 0xFF5555); return end
    ui(o, list)
    return
  end
  if not a:match("^https?://") and not (fs and fs.exists and fs.exists(a)) then
    o("No such file: " .. a, 0xFF5555)
    return
  end
  ui(o, { a })
end

return { commands = { pic = picCmd }, text = V }
