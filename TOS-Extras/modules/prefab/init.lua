-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: prefab — design a base, a slice at a time       ║
-- ║                                                              ║
-- ║  A building is a box of blocks, and a screen is flat, so the ║
-- ║  designer shows one slice of the box at a time, looking      ║
-- ║  along X, Y or Z, with the slice behind it faintly under the ║
-- ║  one being drawn. That faint layer is what makes it feel     ║
-- ║  like 2.5D and not like a stack of unrelated drawings.       ║
-- ║                                                              ║
-- ║  The blueprint and the planning live in blueprint.lua and    ║
-- ║  plan.lua, both pure; this file is the screen and the keys.  ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local B = require("prefab.blueprint")
local P = require("prefab.plan")

local V = {}   -- exported for test_prefab.lua

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
local K = { ENTER = 28, BACK = 14, DEL = 211, TAB = 15, UP = 200, DOWN = 208,
            LEFT = 203, RIGHT = 205, PGUP = 201, PGDN = 209 }

-- ── Text that measures in screen columns ───────────────────────────────
local function ulen(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then n = n + 1 end
  end
  return n
end
local function usub(s, a, b)
  local starts, n = {}, 0
  for i = 1, #s do
    local by = s:byte(i)
    if by < 0x80 or by >= 0xC0 then n = n + 1; starts[n] = i end
  end
  starts[n + 1] = #s + 1
  a, b = math.max(1, a), math.min(n, b)
  if a > b then return "" end
  return s:sub(starts[a], starts[b + 1] - 1)
end
local function pad(s, n)
  s = tostring(s or "")
  local w = ulen(s)
  if w > n then return usub(s, 1, n) end
  return s .. string.rep(" ", n - w)
end

--- The key bar: hints that fit whole, and the way out always last.
function V.fitKeys(hints, out, width)
  local sep = " \194\183 "
  local kept = {}
  for _, h in ipairs(hints) do
    kept[#kept + 1] = h
    if ulen(table.concat(kept, sep) .. sep .. out) > width then kept[#kept] = nil; break end
  end
  if #kept == 0 then return out end
  return table.concat(kept, sep) .. sep .. out
end

--- Plain word wrap.
function V.wrap(text, width)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then line = word
    elseif ulen(line) + 1 + ulen(word) <= width then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

V.KEY_LINES = { "R Rect  C Copy", "V Paste U Undo", "A Add   M Report", "S Save  O Open" }

-- ── The screen ─────────────────────────────────────────────────────────
--- Eight colours a block can be told apart by. Tier 1 has none, so there
--- a block is its letter, reversed.
local T3_BLOCKS = { 0xB0B0B0, 0xC08040, 0x60C0FF, 0x60C060, 0xE06060, 0xE0C040, 0xC060E0, 0x40C0B0 }
local T2_BLOCKS = { 0xCCCCCC, 0xFFCC33, 0x6699FF, 0x33CC33, 0xFF3333, 0xFFFF33, 0xCC66CC, 0x336699 }

local function screen()
  local addr = component.list and component.list("gpu")()
  if not addr then return nil, "no GPU" end
  local okG, gpu = pcall(component.proxy, addr)
  if not okG or not gpu then return nil, "cannot open the GPU" end
  local Wd, Ht = gpu.getResolution()
  if not Wd or Wd < 50 or Ht < 16 then
    return nil, string.format("the designer needs 50x16 (this one is %sx%s)", tostring(Wd), tostring(Ht))
  end
  local okD, depth = pcall(gpu.getDepth)
  local tier = (okD and type(depth) == "number") and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
  local T = (tier == 1) and {
    fg = 0xFFFFFF, dim = 0xFFFFFF, bg = 0x000000, border = 0xFFFFFF, title = 0xFFFFFF,
    hi = 0xFFFFFF, warn = 0xFFFFFF, selfg = 0x000000, selbg = 0xFFFFFF,
  } or {
    fg = 0xFFFFFF, dim = tier == 2 and 0x333333 or 0x666666, bg = 0x000000,
    border = tier == 2 and 0x6699FF or 0x00C0FF, title = tier == 2 and 0xFFFF33 or 0xFFFF00,
    hi = tier == 2 and 0x33CC33 or 0x00FF00, warn = tier == 2 and 0xFF3333 or 0xFF4040,
    selfg = 0x000000, selbg = 0xFFFFFF,
  }
  local S = { W = Wd, H = Ht, tier = tier, T = T, gpu = gpu, mono = tier == 1,
              blocks = tier == 2 and T2_BLOCKS or T3_BLOCKS }
  function S.set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  function S.fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  return S
end

local function saveFile(path, bp)
  if not (fs and fs.writeFile) then return false, "nothing here can write a file" end
  local ok, err = pcall(fs.writeFile, path, B.serialize(bp))
  if not ok or err == false then return false, tostring(err) end
  return true
end

local function loadFile(path)
  if not (fs and fs.exists and fs.exists(path)) then return nil, "no such file: " .. path end
  local ok, data = pcall(fs.readFile, path)
  if not ok or type(data) ~= "string" then return nil, "cannot read " .. path end
  return B.parse(data)
end

--- A new blueprint with a few blocks to start drawing with.
function V.starter(sx, sy, sz, name)
  local bp = B.new(sx, sy, sz, name)
  B.addBlock(bp, "a", "minecraft:cobblestone", 0, "Cobblestone")
  B.addBlock(bp, "b", "minecraft:planks", 0, "Oak Planks")
  B.addBlock(bp, "c", "minecraft:glass", 0, "Glass")
  B.addBlock(bp, "d", "minecraft:stonebrick", 0, "Stone Bricks")
  return bp
end

--- The report's lines, for the screen and the command line.
function V.reportLines(bp, slots)
  local r = P.report(bp, slots)
  local lines = { { string.format("%s: %dx%dx%d, %d blocks", bp.name, bp.sx, bp.sy, bp.sz, r.total), "title" } }
  for _, m in ipairs(r.materials) do
    lines[#lines + 1] = { string.format("%5d  %s  (%s)", m.count, m.label, m.id), "fg" }
  end
  lines[#lines + 1] = { string.format("%d stack(s): %d load(s) for a %d-slot robot", r.stacks, r.trips, slots), "fg" }
  lines[#lines + 1] = { string.format("%d moves along the build order", r.moves), "fg" }
  if #r.floating > 0 then
    local f = r.floating[1]
    lines[#lines + 1] = { string.format("%d floating: nothing to place against, first at %d,%d,%d",
      #r.floating, f[1], f[2], f[3]), "warn" }
  else
    lines[#lines + 1] = { "Every block has something to place against.", "hi" }
  end
  return lines
end

local function pullEvent()
  local e = { computer.pullSignal() }
  if e[1] == "key_down" then return "key", e[3], e[4] end
  if e[1] == "interrupted" then return "key", 17, nil end
  if e[1] == "touch" or e[1] == "drag" then return "mouse", e[3], e[4], e[5], e[1] end
  return e[1]
end

local function ui(o, bp, path)
  local S, why = screen()
  if not S then o("prefab: " .. why .. ". The commands still work: prefab help", 0xFF6600); return end
  local T, Wd, Ht = S.T, S.W, S.H
  local PANEL = math.min(24, math.floor(Wd * 0.34))
  local GX, GY = 1, 3                    -- grid's top left on screen
  local GW = math.floor((Wd - PANEL - 1) / 2)   -- cells across: two columns each
  local GH = Ht - 4                      -- rows of cells
  local PX = Wd - PANEL + 1

  local axis, slice = "y", 1
  local cu, cv = 1, 1                    -- cursor, in view cells
  local su, sv = 0, 0                    -- how far the view has scrolled
  local current = 1                      -- index into bp.order
  local dirty = false
  local undoList = {}
  local clip = nil
  local corner = nil                     -- the rectangle's first corner
  local status, statusTone = nil, "hi"
  local robotSlots = 16

  local function say(m, t) status, statusTone = m, t or "hi" end
  local function tone(t) return T[t] or T.fg end
  local function view() return B.viewSize(bp, axis) end
  local function cellHere(u, v, d)
    return B.get(bp, B.cellOf(bp, axis, u, v, d or slice))
  end
  local function colour(ch)
    for i, c in ipairs(bp.order) do
      if c == ch then return S.blocks[(i - 1) % #S.blocks + 1] end
    end
    return T.fg
  end

  --- One cell. Built: its key on its colour. Empty, with a block in the
  --- slice behind: that key, faint. Otherwise a dot, so the box has edges.
  local function drawCell(u, v)
    local sx = GX + (u - su - 1) * 2
    local sy = GY + (v - sv - 1)
    if sx < GX or sy < GY or u - su > GW or v - sv > GH then return end
    local ch = cellHere(u, v)
    local isCur = (u == cu and v == cv)
    local inCorner = corner and u >= math.min(corner[1], cu) and u <= math.max(corner[1], cu)
      and v >= math.min(corner[2], cv) and v <= math.max(corner[2], cv)
    if isCur then
      S.set(sx, sy, (ch or "+") .. " ", T.selfg, T.selbg)
    elseif inCorner then
      S.set(sx, sy, (ch or " ") .. " ", T.bg, T.hi)
    elseif ch then
      if S.mono then S.set(sx, sy, ch .. " ", T.selfg, T.selbg)
      else S.set(sx, sy, ch .. " ", T.bg, colour(ch)) end
    else
      local behind = cellHere(u, v, slice - 1)
      if behind then S.set(sx, sy, behind .. " ", T.dim, T.bg)
      else S.set(sx, sy, ". ", T.dim, T.bg) end
    end
  end

  local function drawGrid()
    -- To the divider, not to the last cell: an odd width leaves a column
    -- between them, and a pop-up's edge stayed in it on the headless machine.
    S.fill(GX, GY, PX - 2, GH, " ", T.fg, T.bg)
    local uw, vh = view()
    for v = sv + 1, math.min(vh, sv + GH) do
      for u = su + 1, math.min(uw, su + GW) do drawCell(u, v) end
    end
  end

  local AXIS = { x = "X side", y = "Y plan", z = "Z front" }
  local function header()
    S.fill(1, 1, Wd, 1, " ", T.bg, T.border)
    local _, _, deep = view()
    S.set(2, 1, pad(string.format("PREFAB  %s%s", bp.name, dirty and " *" or ""), Wd - 26), T.bg, T.border)
    local right = string.format("%s, slice %d/%d", AXIS[axis], slice, deep)
    S.set(Wd - ulen(right), 1, right, T.bg, T.border)
    S.fill(1, 2, Wd, 1, S.mono and "-" or "─", T.dim, T.bg)
  end

  local function drawPanel()
    S.fill(PX - 1, GY, PANEL + 1, GH, " ", T.fg, T.bg)
    for y = GY, GY + GH - 1 do S.set(PX - 1, y, S.mono and "|" or "│", T.dim, T.bg) end
    local y = GY
    S.set(PX + 1, y, "Blocks", T.dim, T.bg)
    y = y + 1
    for i, ch in ipairs(bp.order) do
      if y > GY + GH - 8 then break end
      local isSel = i == current
      S.set(PX, y, pad((i <= 9 and tostring(i) or " ") .. " " .. ch .. " " .. bp.palette[ch].label, PANEL - 1),
        isSel and T.selfg or T.fg, isSel and T.selbg or T.bg)
      y = y + 1
    end
    --! The rest of the keys live here: the bar holds five at 80 columns, and
    --! Save and Rect fell off the end of it.
    for i, l in ipairs(V.KEY_LINES) do
      S.set(PX + 1, GY + GH - 7 + i, pad(l, PANEL - 2), T.dim, T.bg)
    end
    local x, yy, z = B.cellOf(bp, axis, cu, cv, slice)
    S.set(PX + 1, GY + GH - 2, pad(string.format("At %d,%d,%d", x, yy, z), PANEL - 2), T.dim, T.bg)
    local _, total = B.materials(bp)
    S.set(PX + 1, GY + GH - 1, pad(total .. " blocks", PANEL - 2), T.dim, T.bg)
  end

  local function footer()
    S.fill(1, Ht - 1, Wd, 1, " ", T.fg, T.bg)
    if corner then
      S.set(2, Ht - 1, pad("Move to the far corner, R fills it, Del clears it", Wd - 2), T.title, T.bg)
    elseif status then
      S.set(2, Ht - 1, pad(status, Wd - 2), tone(statusTone), T.bg)
    end
    S.fill(1, Ht, Wd, 1, " ", T.bg, T.border)
    S.set(2, Ht, pad(V.fitKeys({ "Space Paint", "Del Erase", "Tab Block", "XYZ View", "PgUp/Dn Slice" },
      quitLabel() .. " Quit", Wd - 2), Wd - 2), T.bg, T.border)
  end

  local function draw() header(); drawGrid(); drawPanel(); footer() end

  --- Keep the cursor on the screen. Says whether the view moved.
  local function follow()
    local ou, ov = su, sv
    if cu <= su then su = cu - 1 elseif cu > su + GW then su = cu - GW end
    if cv <= sv then sv = cv - 1 elseif cv > sv + GH then sv = cv - GH end
    return ou ~= su or ov ~= sv
  end

  local function moveTo(u, v)
    local uw, vh = view()
    local ou, ov = cu, cv
    cu, cv = math.max(1, math.min(uw, u)), math.max(1, math.min(vh, v))
    if follow() or corner then drawGrid() else drawCell(ou, ov); drawCell(cu, cv) end
    drawPanel()
  end

  local function remember(u)
    if not u then return end
    undoList[#undoList + 1] = u
    if #undoList > 32 then table.remove(undoList, 1) end
    dirty = true
  end

  local function setView(a)
    axis, slice = a, 1
    cu, cv, su, sv = 1, 1, 0, 0
    corner = nil
    draw()
  end

  -- ── Pop-ups, in the shell's dialog style ───────────────────────────
  local function box(title, x, y, w, h)
    local mono = S.mono
    local hz, vt = mono and "=" or "═", mono and "|" or "║"
    if not mono then
      S.set(x + 1, y + h, string.rep(" ", w), T.bg, 0x1A1A1A)
      S.fill(x + w, y + 1, 1, h, " ", T.bg, 0x1A1A1A)
    end
    local inner = string.rep(hz, w - 2)
    S.set(x, y, (mono and "+" or "╔") .. inner .. (mono and "+" or "╗"), T.border, T.bg)
    S.set(x, y + h - 1, (mono and "+" or "╚") .. inner .. (mono and "+" or "╝"), T.border, T.bg)
    S.fill(x, y + 1, 1, h - 2, vt, T.border, T.bg)
    S.fill(x + w - 1, y + 1, 1, h - 2, vt, T.border, T.bg)
    S.fill(x + 1, y + 1, w - 2, h - 2, " ", T.fg, T.bg)
    local label = pad(title, math.min(ulen(title), w - 6))
    S.set(x + math.floor((w - ulen(label) - 4) / 2), y,
      (mono and "[ " or "╡ ") .. label .. (mono and " ]" or " ╞"), T.title, T.bg)
  end

  local function popup(title, lines, hint, rows)
    draw()
    local w = math.min(Wd - 6, 64)
    local n = math.min(#lines, Ht - 6 - rows)
    local h = n + rows + 4
    local x, y = math.floor((Wd - w) / 2) + 1, math.floor((Ht - h) / 2) + 1
    box(title, x, y, w, h)
    for i = 1, n do S.set(x + 2, y + i, pad(lines[i][1], w - 4), tone(lines[i][2]), T.bg) end
    S.set(x + 2, y + h - 2, pad(hint, w - 4), T.dim, T.bg)
    return x, y + n + 1, w
  end

  local function nextKey()
    while true do
      local kind, a, b = pullEvent()
      if kind == "key" then return a, b end
    end
  end

  local function prompt(title, label, initial)
    local buf = tostring(initial or "")
    local fresh = buf ~= ""              -- the first letter typed replaces it
    local x, y, w = popup(title, { { label, "fg" } }, "Enter OK · " .. quitLabel() .. " cancel", 1)
    while true do
      local line = buf .. "_"
      local over = ulen(line) - (w - 4)
      if over > 0 then line = usub(line, over + 1, ulen(line)) end
      S.set(x + 2, y, pad(line, w - 4), T.title, T.bg)
      local ch, code = nextKey()
      if code == K.ENTER then return buf end
      if isQuit(ch, code) then return nil end
      if code == K.BACK then buf = buf:sub(1, -2)
      elseif ch and ch >= 32 and ch < 127 then
        if fresh then buf = "" end
        buf = buf .. string.char(ch)
      end
      fresh = false
    end
  end

  local function yesNo(question)
    local lines = {}
    for _, l in ipairs(V.wrap(question, 56)) do lines[#lines + 1] = { l, "warn" } end
    popup("Confirm", lines, "Y Yes · N No", 0)
    while true do
      local ch, code = nextKey()
      if isQuit(ch, code) then return false end
      if ch and ch > 0 then
        local c = string.char(ch):lower()
        if c == "y" then return true end
        if c == "n" then return false end
      end
    end
  end

  local function addBlock()
    local ch = B.freeKey(bp)
    if not ch then say("Every key is taken.", "warn"); return end
    local id = prompt("Add a block", "Registry name, like minecraft:stone:", "")
    if not id or id == "" then return end
    local label = prompt("Add a block", "What to call it:", (id:match(":(.+)$") or id))
    if not label then return end
    local meta = prompt("Add a block", "Damage value (0 for most blocks):", "0")
    if not meta then return end
    local ok, err = B.addBlock(bp, ch, id, tonumber(meta) or -1, B.cleanName(label))
    if not ok then say("Not added: " .. err, "warn"); return end
    current = #bp.order
    dirty = true
    say("Added " .. bp.palette[ch].label .. " as " .. ch .. ".")
  end

  local function report()
    popup("What this takes", V.reportLines(bp, robotSlots), "Any key to go back", 0)
    nextKey()
  end

  local function save()
    local name = prompt("Save blueprint", "File:", path or (bp.name:gsub("%W+", "-"):lower() .. ".bp"))
    if not name or name == "" then return end
    local ok, err = saveFile(name, bp)
    if ok then path, dirty = name, false; say("Saved " .. name .. ".")
    else say("NOT saved: " .. tostring(err), "warn") end
  end

  local function open()
    if dirty and not yesNo("Open another without saving this one?") then return end
    local name = prompt("Open blueprint", "File:", path or "")
    if not name or name == "" then return end
    local loaded, err = loadFile(name)
    if not loaded then say("Cannot open: " .. tostring(err), "warn"); return end
    bp, path, dirty, undoList, current = loaded, name, false, {}, 1
    axis, slice, cu, cv, su, sv = "y", 1, 1, 1, 0, 0
    say("Opened " .. name .. ".")
  end

  local function paintHere(ch)
    remember(B.paint(bp, { { B.cellOf(bp, axis, cu, cv, slice) } }, ch))
  end

  local function selected() return bp.order[current] end

  draw()
  while true do
    local kind, ch, code, button, how = pullEvent()
    local redraw = true
    if kind == "tos_focus" then draw(); redraw = false
    elseif kind == "mouse" then
      -- ch and code carry x and y here: OC's touch is (x, y, button).
      local mx, my = ch, code
      if mx < PX - 1 and my >= GY and my < GY + GH then
        local uw, vh = view()
        local u = math.floor((mx - GX) / 2) + 1 + su
        local v = my - GY + 1 + sv
        if u <= uw and v <= vh then
          cu, cv = u, v
          if button == 1 then paintHere(nil) else paintHere(selected()) end
        end
      elseif how == "touch" and mx >= PX and my > GY and my <= GY + #bp.order then
        current = my - GY
      end
    elseif kind == "key" then
      status = nil
      local c = ch and ch > 0 and string.char(ch):lower() or ""
      local _, _, deep = view()
      if isQuit(ch, code) then
        if corner then corner = nil
        elseif not dirty or yesNo("Leave without saving?") then break end
      elseif code == K.LEFT then moveTo(cu - 1, cv); redraw = false; footer()
      elseif code == K.RIGHT then moveTo(cu + 1, cv); redraw = false; footer()
      elseif code == K.UP then moveTo(cu, cv - 1); redraw = false; footer()
      elseif code == K.DOWN then moveTo(cu, cv + 1); redraw = false; footer()
      elseif code == K.PGUP then slice = math.min(deep, slice + 1)
      elseif code == K.PGDN then slice = math.max(1, slice - 1)
      elseif code == K.TAB then current = current % math.max(1, #bp.order) + 1
      elseif c == " " then if corner then corner = nil else paintHere(selected()) end
      elseif code == K.DEL or code == K.BACK then
        if corner then
          remember(B.paint(bp, B.rect(bp, axis, slice, corner[1], corner[2], cu, cv), nil))
          corner = nil
        else paintHere(nil) end
      elseif c == "x" or c == "y" or c == "z" then setView(c)
      elseif c == "r" then
        if corner then
          remember(B.paint(bp, B.rect(bp, axis, slice, corner[1], corner[2], cu, cv), selected()))
          corner = nil
        else corner = { cu, cv } end
      elseif c == "c" then
        clip = B.copySlice(bp, axis, slice)
        say("Copied this slice. Move to another, and V pastes it.")
      elseif c == "v" then
        if not clip then say("Nothing copied yet: C copies this slice.", "warn")
        else
          local u, err = B.pasteSlice(bp, clip, axis, slice)
          if err then say(err, "warn") else remember(u) end
        end
      elseif c == "u" then
        local u = table.remove(undoList)
        if u then B.undo(bp, u); dirty = true else say("Nothing to undo.", "warn") end
      elseif c == "a" then addBlock()
      elseif c == "m" then report()
      elseif c == "s" then save()
      elseif c == "o" then open()
      elseif c:match("%d") and bp.order[tonumber(c)] then current = tonumber(c)
      end
    else
      redraw = false
    end
    if redraw then draw() end
  end
  S.fill(1, 1, Wd, Ht, " ", T.fg, T.bg)
end

-- ── Command line ───────────────────────────────────────────────────────
local function help(o)
  o("prefab — design a base, a slice at a time", 0xFFFF55)
  o("  prefab                       a new blueprint, 16x8x16", 0xFFFFFF)
  o("  prefab <file.bp>             open one", 0xFFFFFF)
  o("  prefab new <x> <y> <z> [name]  a new one of that size", 0xFFFFFF)
  o("  prefab info <file.bp> [slots]  what it takes to build", 0xFFFFFF)
  o("  In the designer: Space paint, X Y Z change the view, PgUp/PgDn change the slice.", 0xAAAAAA)
end

local function prefabCmd(args, o)
  args = args or {}
  o = o or print
  local a = args[1]
  if a == "help" or a == "--help" or a == "-h" then help(o); return end
  if a == "info" then
    if not args[2] then o("Which blueprint?", 0xFF5555); return end
    local bp, err = loadFile(args[2])
    if not bp then o(tostring(err), 0xFF5555); return end
    local slots = math.max(1, math.min(64, tonumber(args[3]) or 16))
    local colours = { title = 0xFFFF55, fg = 0xFFFFFF, hi = 0x55FF55, warn = 0xFF5555 }
    for _, l in ipairs(V.reportLines(bp, slots)) do o(l[1], colours[l[2]]) end
    return
  end
  if a == "new" then
    local x, y, z = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    local function side(n) return n and n >= 1 and n <= B.MAX_SIDE and n == math.floor(n) end
    if not (side(x) and side(y) and side(z)) then
      o("prefab new <x> <y> <z>: each side is 1 to " .. B.MAX_SIDE, 0xFF5555)
      return
    end
    local name = B.cleanName(table.concat(args, " ", 5))
    ui(o, V.starter(x, y, z, name ~= "" and name or nil))
    return
  end
  if not a then ui(o, V.starter(16, 8, 16)); return end
  local bp, err = loadFile(a)
  if not bp then o(tostring(err), 0xFF5555); return end
  ui(o, bp, a)
end

return { commands = { prefab = prefabCmd }, text = V }
