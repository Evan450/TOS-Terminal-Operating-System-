-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
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
local G = require("prefab.survey")
local E = require("prefab.export")
local L = require("prefab.links")
local Base = require("prefab.base")
local Parts = require("prefab.parts")

local V = {}   -- exported for test_prefab.lua

local U = require("prefab.tui").new(component, computer, (function()
  local okK, m = pcall(require, "shell.keys")
  return okK and m or nil
end)())
local isQuit, quitLabel, K = U.isQuit, U.quitLabel, U.K
local ulen, pad = U.ulen, U.pad
V.fitKeys, V.wrap = U.fitKeys, U.wrap

V.KEY_LINES = { "R Rect  C Copy", "V Paste U Undo", "A Add   M Report", "S Save  O Open" }

--! The sandbox's fs.writeFile refuses by returning false and a reason, not
--! by throwing, so `pcall` alone calls a refused write a success, and its
--! second value is only that false. (test_prefab_links.lua)
local function writeFile(path, data)
  if not (fs and fs.writeFile) then return false, "nothing here can write a file" end
  local ok, done, why = pcall(fs.writeFile, path, data)
  if not ok then return false, tostring(done) end
  if done == false or done == nil then return false, tostring(why or "the write was refused") end
  return true
end

local function saveFile(path, bp) return writeFile(path, B.serialize(bp)) end

--- A file's text, or nil: how a base reaches a part of your own.
local function readText(path)
  if not (fs and fs.exists and fs.exists(path)) then return nil end
  local ok, data = pcall(fs.readFile, path)
  if ok and type(data) == "string" then return data end
end

--! A base compiles here, so everything that loads a blueprint takes a base
--! and none of it needs to know: survey, export, need, print, csv.
local function loadFile(path)
  if not (fs and fs.exists and fs.exists(path)) then return nil, "no such file: " .. path end
  local data = readText(path)
  if not data then return nil, "cannot read " .. path end
  if Base.is(data) then
    local base, err = Base.parse(data)
    if not base then return nil, err end
    return Base.compile(base, readText)
  end
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

local function ui(o, bp, path)
  local S, why = U.screen()
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

  local kit = U.kit(S, draw)
  local popup, nextKey, prompt, yesNo = kit.popup, kit.nextKey, kit.prompt, kit.yesNo

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
    local kind, ch, code, button, how = U.pullEvent()
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

-- ── Survey ─────────────────────────────────────────────────────────────
--- `prefab survey`'s words: a blueprint or a size, then options. Returns
--- { path, w, d, height, at = { x, z }, down, up }, or nil and why.
function V.parseSurvey(args)
  local opt = { down = 8 }
  local pos = {}
  local i = 2
  while i <= #args do
    local a = args[i]
    if a == "--at" then
      local x, z = tonumber(args[i + 1]), tonumber(args[i + 2])
      if not x or not z then return nil, "--at needs an X and a Z" end
      opt.at = { x = math.floor(x), z = math.floor(z) }
      i = i + 3
    elseif a == "--down" or a == "--up" or a == "--height" then
      local n = tonumber(args[i + 1])
      if not n or n < 0 then return nil, a .. " needs a number" end
      opt[a:sub(3)] = math.floor(n)
      i = i + 2
    elseif a:sub(1, 2) == "--" then
      return nil, "unknown option " .. a
    else
      pos[#pos + 1] = a
      i = i + 1
    end
  end
  if #pos == 1 then opt.path = pos[1]
  elseif #pos == 2 and tonumber(pos[1]) and tonumber(pos[2]) then
    opt.w, opt.d = math.floor(tonumber(pos[1])), math.floor(tonumber(pos[2]))
  else
    return nil, "prefab survey <file.bp>, or prefab survey <width> <depth>"
  end
  return opt
end

--- The box a survey reads. With no --at the site sits around the geolyzer.
function V.surveyBox(opt)
  local at = opt.at or { x = -math.floor(opt.w / 2), z = -math.floor(opt.d / 2) }
  local up = opt.up or (opt.height + 8)
  return { x = at.x, z = at.z, y = -opt.down, w = opt.w, d = opt.d, h = opt.down + up + 1 }
end

--- A signed height, the way a player reads an offset.
local function signed(n) return (n > 0 and "+" or "") .. n end

--- The survey's report: what the best floor costs, and the site from above.
function V.surveyLines(site, height)
  local lines = {}
  local levels = G.fit(site, height)
  local L = levels[1]
  if not L then
    return { { "That band is too thin to fit a floor and " .. height .. " layers: raise --up or --down.", "warn" } }
  end
  lines[1] = { string.format("Best floor: Y %s from the geolyzer", signed(L.y)), "title" }
  lines[#lines + 1] = { string.format("%d block(s) in the way, %d to fill under the floor", L.clear, L.fill), "fg" }
  if L.over > 0 then
    lines[#lines + 1] = { string.format("%d more above the building, in a robot's way down", L.over), "fg" }
  end
  if L.liquid > 0 then
    lines[#lines + 1] = { string.format("%d cell(s) of liquid in the building's space", L.liquid), "warn" }
  end
  if L.fixed > 0 then
    lines[#lines + 1] = { string.format("%d cell(s) that cannot be broken", L.fixed), "warn" }
  end
  if L.open > 0 then
    lines[#lines + 1] = { string.format(
      "%d column(s) with nothing under them in the scan: a deep hole, or an unloaded chunk",
      L.open), "warn" }
  end
  if levels[2] then
    local n = levels[2]
    lines[#lines + 1] = { string.format("Next best: Y %s, %d in the way, %d to fill",
      signed(n.y), n.clear, n.fill), "dim" }
  end
  lines[#lines + 1] = { string.format("The site from above, X east and Z south, corner at %s,%s:",
    signed(site.x), signed(site.z)), "dim" }
  for _, row in ipairs(G.map(site, L.y)) do lines[#lines + 1] = { row, "fg" } end
  lines[#lines + 1] = { ". ready  1-9 too high  a-i too low  ~ liquid  ? nothing read", "dim" }
  return lines
end

local function cliSurvey(args, o)
  local colours = { title = 0xFFFF55, fg = 0xFFFFFF, dim = 0xAAAAAA, warn = 0xFF5555 }
  local opt, err = V.parseSurvey(args)
  if not opt then o(err, 0xFF5555); return end
  if opt.path then
    local bp, bErr = loadFile(opt.path)
    if not bp then o(tostring(bErr), 0xFF5555); return end
    opt.w, opt.d = bp.sx, bp.sz
    opt.height = opt.height or bp.sy
  end
  opt.height = opt.height or 8
  local box = V.surveyBox(opt)
  local bad = G.check(box)
  if bad then o(bad, 0xFF5555); return end
  local addr = component.list and component.list("geolyzer")()
  if not addr then
    o("No geolyzer: this needs one attached, or in a robot or tablet running it.", 0xFF5555)
    return
  end
  local geo = component.proxy(addr)
  local calls = G.calls(box.w, box.d, box.h)
  o(string.format("Reading %dx%dx%d: %d scans, about %d s and %d energy.", box.w, box.d, box.h,
    calls, math.ceil(calls / G.RATE), calls * G.COST), 0xAAAAAA)
  local site
  site, err = G.survey(geo.scan, box, { wait = function() computer.pullSignal(1) end })
  if not site then o("The survey stopped: " .. tostring(err), 0xFF5555); return end
  for _, l in ipairs(V.surveyLines(site, opt.height)) do o(l[1], colours[l[2]]) end
end

-- ── Export ─────────────────────────────────────────────────────────────
--- `prefab export`'s words. Returns in, out, slots, chest and clear, or nil
--- and why.
function V.parseExport(args)
  local pos, slots, chest, clear = {}, 16, false, false
  local i = 2
  while i <= #args do
    local a = args[i]
    if a == "--slots" then
      slots = tonumber(args[i + 1])
      if not slots or slots < 1 or slots > 64 then return nil, "--slots is 1 to 64" end
      slots = math.floor(slots)
      i = i + 2
    elseif a == "--chest" then
      chest = true
      i = i + 1
    elseif a == "--clear" then
      clear = true
      i = i + 1
    elseif a:sub(1, 2) == "--" then
      return nil, "unknown option " .. a
    else
      pos[#pos + 1] = a
      i = i + 1
    end
  end
  if #pos ~= 2 then return nil, "prefab export <file.bp> <out.lua> [--slots N] [--chest] [--clear]" end
  return pos[1], pos[2], slots, chest, clear
end

--- What to tell whoever is about to carry the program to a robot.
function V.exportLines(path, info)
  local lines = { { string.format("Wrote %s: %d steps, %d moves, about %d s and %d energy.", path,
    info.steps, info.moves, info.seconds, math.ceil(info.energy)), "hi" } }
  if info.chest then
    lines[#lines + 1] = { "Put a chest right behind the robot, holding:", "fg" }
    for _, l in ipairs(info.sheet) do
      lines[#lines + 1] = { string.format("  %5d  %s", l.count, l.label), "fg" }
    end
    lines[#lines + 1] = { string.format("It needs an inventory controller, and makes %d trip(s) to the chest.", info.trips), "dim" }
    if info.clear then
      lines[#lines + 1] = { string.format("It clears %d cells first, plus the time to dig them, so it needs a pickaxe.", info.site), "warn" }
      lines[#lines + 1] = { "Debris goes in the chest: use a double chest, and put spare pickaxes in it.", "dim" }
    end
  else
    lines[#lines + 1] = { "Load the robot:", "fg" }
    for _, l in ipairs(info.sheet) do
      lines[#lines + 1] = { string.format("  slot %-5s %d  %s", l.slots, l.count, l.label), "fg" }
    end
    if info.loads > 1 then
      lines[#lines + 1] = { string.format("That is %d loads: it walks back to the corner and waits for each.", info.loads), "warn" }
    end
  end
  if info.hover then
    lines[#lines + 1] = { string.format("Needs a hover upgrade from step %d: there is nothing near enough to fly over.", info.hover), "warn" }
  end
  lines[#lines + 1] = { "Stand it in the corner of the first layer, at the floor the survey found.", "dim" }
  lines[#lines + 1] = { "The building goes ahead of it and to its right. On OpenOS, run the file.", "dim" }
  return lines
end

local function cliExport(args, o)
  local colours = { hi = 0x55FF55, fg = 0xFFFFFF, dim = 0xAAAAAA, warn = 0xFF5555 }
  local src, dest, slots, chest, clear = V.parseExport(args)
  if not src then o(dest, 0xFF5555); return end
  local bp, err = loadFile(src)
  if not bp then o(tostring(err), 0xFF5555); return end
  local program, info = E.program(bp, { slots = slots, chest = chest, clear = clear })
  if not program then o("Cannot export: " .. tostring(info), 0xFF5555); return end
  local ok, wErr = writeFile(dest, program)
  if not ok then o("Not saved: " .. tostring(wErr), 0xFF5555); return end
  for _, l in ipairs(V.exportLines(dest, info)) do o(l[1], colours[l[2]]) end
end

-- ── With the rest of the pack ──────────────────────────────────────────
-- Each of these asks for the other package when it is used, not at load,
-- so prefab works exactly the same on a machine without it.
local function optional(name)
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then return mod end
end

--- What is in reach, or nil and why. Nothing here needs the stock package:
--- the inventory library belongs to the base.
local function readStacks()
  local inv = optional("peripheral.inventory")
  if not inv then return nil, "inventory support is not available here" end
  return L.scan(inv)
end

local function blueprintArg(args, o)
  if not args[2] then o("Which blueprint?", 0xFF5555); return nil end
  local bp, err = loadFile(args[2])
  if not bp then o(tostring(err), 0xFF5555) end
  return bp
end

local function cliNeed(args, o)
  local bp = blueprintArg(args, o)
  if not bp then return end
  local stacks, names = readStacks()
  if not stacks then o("Cannot read your inventories: " .. tostring(names), 0xFF5555); return end
  local rows, short = L.need(bp, stacks)
  o(string.format("%s, against what is on: %s", bp.name, table.concat(names, ", ")), 0xFFFF55)
  for _, r in ipairs(rows) do
    o(string.format("%5d of %-5d %s%s", math.min(r.have, r.need), r.need, r.label,
      r.short > 0 and string.format("  (%d short)", r.short) or ""),
      r.short > 0 and 0xFF5555 or 0xFFFFFF)
  end
  if short == 0 then o("You have everything it takes.", 0x55FF55)
  else
    o(string.format("%d block(s) short.", short), 0xFF5555)
    if optional("stock.stock") then
      o("prefab watch puts these on stock's monitor.", 0xAAAAAA)
    end
  end
end

local function cliWatch(args, o)
  local bp = blueprintArg(args, o)
  if not bp then return end
  local S = optional("stock.stock")
  if not S then o("This needs the stock package: pkg install stock", 0xFF5555); return end
  if not S.saveWatches then o("This needs stock 1.0.2: pkg upgrade stock", 0xFF5555); return end
  local watches, labels = S.readWatches(fs)
  local off = args[3] == "--off"
  local n = (off and L.unwatch or L.watch)(watches, labels, bp)
  local ok, err = S.saveWatches(fs, watches, labels)
  if not ok then
    o("Not saved: " .. tostring(err) .. " (stock's list needs an admin)", 0xFF5555)
    return
  end
  if off then o(string.format("stock stopped watching %d block(s) for %s.", n, bp.name), 0x55FF55)
  else
    o(string.format("stock is watching %d block(s) for %s.", n, bp.name), 0x55FF55)
    o("`stock low` lists what is short, and the monitor flags it.", 0xAAAAAA)
  end
end

local function cliPrint(args, o)
  local bp = blueprintArg(args, o)
  if not bp then return end
  local PR, fmt = optional("printer"), optional("printerfmt")
  if not PR or not fmt then o("This needs the printer package: pkg install printer", 0xFF5555); return end
  local dry = args[3] == "--dry"
  if not dry and not PR.available() then
    o("No printer: " .. tostring(PR.unavailableReason and PR.unavailableReason() or "none attached"), 0xFF5555)
    return
  end
  local width = PR.available() and PR.maxWidth() or fmt.MAX_WIDTH
  local job = L.printJob(PR.job(bp.name), bp, P.report(bp, 16), width)
  local cost = job:cost()
  o(string.format("%d page(s): %d sheet(s), %d black ink.", #job:pages(), cost.paper, cost.black), 0xFFFFFF)
  if dry then return end
  local done, err, pages = job:commit()
  if not done then
    o(string.format("Stopped after %d page(s): %s", pages or 0, tostring(err)), 0xFF5555)
    return
  end
  o(string.format("Printed %d page(s).", done), 0x55FF55)
end

local function cliCsv(args, o)
  local bp = blueprintArg(args, o)
  if not bp then return end
  local dest = args[3]
  if not dest then o("prefab csv <file.bp> <out.csv>", 0xFF5555); return end
  local stacks = readStacks()
  local rows = stacks and L.need(bp, stacks) or nil
  local ok, err = writeFile(dest, L.csv(bp, rows))
  if not ok then o("Not saved: " .. tostring(err), 0xFF5555); return end
  o("Wrote " .. dest .. (rows and ", with what you have in it." or "."), 0x55FF55)
  if fs.exists and fs.exists("/usr/modules/calc/init.lua") then
    o("calc " .. dest .. " opens it as a worksheet.", 0xAAAAAA)
  end
end

-- ── Command line ───────────────────────────────────────────────────────
local function help(o)
  o("prefab — design a base, a slice at a time", 0xFFFF55)
  o("  prefab                       a new blueprint, 16x8x16", 0xFFFFFF)
  o("  prefab <file.bp>             open one", 0xFFFFFF)
  o("  prefab new <x> <y> <z> [name]  a new one of that size", 0xFFFFFF)
  o("  prefab info <file.bp> [slots]  what it takes to build", 0xFFFFFF)
  o("  prefab survey <file.bp>      read the site with a geolyzer", 0xFFFFFF)
  o("  prefab survey <w> <d> [--height N] [--at X Z] [--down N] [--up N]", 0xFFFFFF)
  o("  prefab export <file.bp> <out.lua> [--slots N] [--chest] [--clear]   a program for a robot", 0xFFFFFF)
  o("  prefab parts                 the parts a base is built from", 0xFFFFFF)
  o("  prefab base <w> <d> [name]   lay out a new base, in tiles", 0xFFFFFF)
  o("  prefab check <file.base>     doors that lead nowhere, rooms cut off", 0xFFFFFF)
  o("  prefab compile <file.base> <out.bp>   the base as one blueprint", 0xFFFFFF)
  o("  A .base works anywhere a .bp does: survey, export, need, print, csv.", 0xAAAAAA)
  o("  prefab need <file.bp>        what you have against what it takes", 0xFFFFFF)
  o("  prefab watch <file.bp> [--off]   put its materials on stock's watch list", 0xFFFFFF)
  o("  prefab print <file.bp> [--dry]   print its plans", 0xFFFFFF)
  o("  prefab csv <file.bp> <out.csv>   its materials, for calc or anything else", 0xFFFFFF)
  o("  In the designer: Space paint, X Y Z change the view, PgUp/PgDn change the slice.", 0xAAAAAA)
end

local function layout(o, base, path)
  require("prefab.layout").run(o, { U = U, read = readText, write = writeFile,
    reportLines = function(bp) return V.reportLines(bp, 16) end }, base, path)
end

local function cliParts(o)
  o(string.format("Each tile is %d by %d, %d high. A door is the middle of a tile's edge.", Parts.TILE, Parts.TILE, Parts.HEIGHT), 0xAAAAAA)
  for _, p in ipairs(Parts.LIBRARY) do
    o(string.format("  %-9s %-26s doors %s", p.name, p.label, Parts.doorText((Parts.doors(p.bp)))), 0xFFFFFF)
  end
  o("Your own blueprint is a part too, if whole tiles: prefab new 7 5 7", 0xAAAAAA)
end

local function baseArg(args, o)
  if not args[2] then o("Which base?", 0xFF5555); return nil end
  local text = readText(args[2])
  if not text then o("no such file: " .. args[2], 0xFF5555); return nil end
  local base, err = Base.parse(text)
  if not base then o(tostring(err), 0xFF5555) end
  return base
end

local function cliCheck(args, o)
  local base = baseArg(args, o)
  if not base then return end
  local r, err = Base.check(base, readText)
  if not r then o(tostring(err), 0xFF5555); return end
  for _, p in ipairs(r.problems) do o(p, 0xFF5555) end
  if #r.problems == 0 then
    o(base.name .. ": " .. Base.summary(r), 0x55FF55)
  end
end

local function cliCompile(args, o)
  local base = baseArg(args, o)
  if not base then return end
  if not args[3] then o("prefab compile <file.base> <out.bp>", 0xFF5555); return end
  local bp, err = Base.compile(base, readText)
  if not bp then o(tostring(err), 0xFF5555); return end
  local ok, wErr = writeFile(args[3], B.serialize(bp))
  if not ok then o("Not saved: " .. tostring(wErr), 0xFF5555); return end
  o(string.format("Wrote %s: %dx%dx%d.", args[3], bp.sx, bp.sy, bp.sz), 0x55FF55)
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
  if a == "parts" then cliParts(o); return end
  if a == "check" then cliCheck(args, o); return end
  if a == "compile" then cliCompile(args, o); return end
  if a == "base" then
    local w, d = tonumber(args[2]), tonumber(args[3])
    if not (w and d and w >= 1 and d >= 1 and w <= Base.MAX_TILES and d <= Base.MAX_TILES and w == math.floor(w) and d == math.floor(d)) then
      o("prefab base <w> <d> [name]: each side is 1 to " .. Base.MAX_TILES .. " tiles", 0xFF5555)
      return
    end
    local name = B.cleanName(table.concat(args, " ", 4))
    layout(o, Base.new(w, d, name ~= "" and name or nil))
    return
  end
  if a == "survey" then cliSurvey(args, o); return end
  if a == "export" then cliExport(args, o); return end
  if a == "need" then cliNeed(args, o); return end
  if a == "watch" then cliWatch(args, o); return end
  if a == "print" then cliPrint(args, o); return end
  if a == "csv" then cliCsv(args, o); return end
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
  -- Open a base as the base it is, not as what it compiles to.
  if Base.is(readText(a)) then
    local base, bErr = Base.parse(readText(a))
    if not base then o(tostring(bErr), 0xFF5555); return end
    layout(o, base, a)
    return
  end
  local bp, err = loadFile(a)
  if not bp then o(tostring(err), 0xFF5555); return end
  ui(o, bp, a)
end

return { commands = { prefab = prefabCmd }, text = V }
