-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: prefab, from a blueprint file to the keys             ║
-- ║                                                              ║
-- ║  The blueprint and the planner are tested on their own; the  ║
-- ║  last section runs the real init.lua in a fake sandbox, with ║
-- ║  a GPU that keeps a screen buffer, and draws a small hut the ║
-- ║  way an operator would, with keys and with the mouse.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/prefab/test_prefab.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "modules/?.lua;" .. package.path
local B = require("prefab.blueprint")
local P = require("prefab.plan")
local G = require("prefab.survey")

print("=== the blueprint ===")
print()

local HUT = [[
PREFAB1
name Starter hut
size 5 2 3
block a minecraft:cobblestone 0 Cobblestone
block g minecraft:glass 0 Glass
layer 1
aaaaa
aaaaa
aaaaa
layer 2
agaga
a...a
aaaaa
]]

do
  local bp, err = B.parse(HUT)
  test("the format's own example parses", bp ~= nil, err)
  test("...with its name and size", bp.name == "Starter hut" and bp.sx == 5 and bp.sy == 2 and bp.sz == 3)
  test("...and its blocks", bp.palette.g.id == "minecraft:glass" and bp.palette.a.label == "Cobblestone")
  test("a cell reads back", B.get(bp, 2, 2, 1) == "g" and B.get(bp, 1, 1, 1) == "a")
  test("air is nothing", B.get(bp, 2, 2, 2) == nil)
  test("outside the box is nothing", B.get(bp, 9, 1, 1) == nil and B.get(bp, 0, 1, 1) == nil)
  test("it writes back byte for byte", B.serialize(bp) == HUT)
end

do
  local function bad(text, needle)
    local bp, err = B.parse(text)
    test("refused: " .. needle, bp == nil and tostring(err):find(needle, 1, true) ~= nil, err)
  end
  bad("hello", "not a blueprint")
  bad("PREFAB1\nname x\n", "no size")
  bad("PREFAB1\nsize 0 1 1\n", "each side")
  bad("PREFAB1\nsize 999 1 1\n", "each side")
  bad("PREFAB1\nblock a b:c 0 x\n", "size comes first")
  bad("PREFAB1\nsize 2 1 1\nblock a nocolon 0 x\n", "modname:blockname")
  bad("PREFAB1\nsize 2 1 1\nblock aa b:c 0 x\n", "one letter or digit")
  bad("PREFAB1\nsize 2 1 1\nlayer 5\n", "no such layer")
  bad("PREFAB1\nsize 2 1 1\nlayer 1\nabc\n", "a row is 2 wide")
  bad("PREFAB1\nsize 2 1 1\nlayer 1\nzz\n", "no block 'z'")
  bad("PREFAB1\nsize 1 1 1\nblock a b:c 0 x\nlayer 1\na\na\n", "too many rows")
  bad("PREFAB1\nsize 1 1 1\nwhat\n", "what is this")
  test("CRLF line ends read the same", B.parse((HUT:gsub("\n", "\r\n"))) ~= nil)
end

do
  -- Slices: every view of a cell agrees about which cell it is.
  local bp = B.new(4, 3, 2)
  test("a plan is X across, Z down, Y deep", select(1, B.viewSize(bp, "y")) == 4
    and select(2, B.viewSize(bp, "y")) == 2 and select(3, B.viewSize(bp, "y")) == 3)
  test("a front view is X across, Y down, Z deep", select(2, B.viewSize(bp, "z")) == 3
    and select(3, B.viewSize(bp, "z")) == 2)
  test("a side view is Z across, Y down, X deep", select(1, B.viewSize(bp, "x")) == 2
    and select(3, B.viewSize(bp, "x")) == 4)
  local x, y, z = B.cellOf(bp, "z", 2, 1, 1)
  test("the top row of a front view is the top of the box", x == 2 and y == 3 and z == 1)
  x, y, z = B.cellOf(bp, "x", 1, 3, 4)
  test("the bottom row of a side view is the ground", x == 4 and y == 1 and z == 1)
  local all = {}
  for _, axis in ipairs({ "x", "y", "z" }) do
    local uw, vh, deep = B.viewSize(bp, axis)
    local seen, n = {}, 0
    for d = 1, deep do for v = 1, vh do for u = 1, uw do
      local a, b, c = B.cellOf(bp, axis, u, v, d)
      local k = a .. "," .. b .. "," .. c
      if not seen[k] and B.inside(bp, a, b, c) then seen[k] = true; n = n + 1 end
    end end end
    all[axis] = n
  end
  test("each view reaches every cell exactly once", all.x == 24 and all.y == 24 and all.z == 24)
end

do
  local bp = B.new(3, 1, 3)
  B.addBlock(bp, "a", "m:a", 0, "A")
  local u = B.paint(bp, B.rect(bp, "y", 1, 3, 3, 2, 2), "a")
  test("a rectangle takes either corner first", B.get(bp, 2, 1, 2) == "a" and B.get(bp, 3, 1, 3) == "a"
    and B.get(bp, 1, 1, 1) == nil)
  test("painting says how to undo", u ~= nil and #u == 4)
  test("painting what is there already changes nothing", B.paint(bp, B.rect(bp, "y", 1, 2, 2, 3, 3), "a") == nil)
  B.undo(bp, u)
  test("undo puts it back", B.get(bp, 2, 1, 2) == nil and next(bp.cells) == nil)
  test("a corner past the box is ignored", B.paint(bp, { { 9, 9, 9 } }, "a") == nil)

  local tall = B.new(2, 3, 2)
  B.addBlock(tall, "a", "m:a", 0, "A")
  B.paint(tall, B.rect(tall, "y", 1, 1, 1, 2, 2), "a")
  local clip = B.copySlice(tall, "y", 1)
  local up = B.pasteSlice(tall, clip, "y", 3)
  test("a copied slice pastes onto another", B.get(tall, 2, 3, 2) == "a" and up ~= nil)
  test("...and undoes as one step", (function() B.undo(tall, up); return B.get(tall, 2, 3, 2) == nil end)())
  test("a slice from another view is refused", select(2, B.pasteSlice(tall, clip, "x", 1)) ~= nil)

  local mats, total = B.materials(B.parse(HUT))
  test("materials count, most used first", total == 27 and mats[1].key == "a" and mats[1].count == 25
    and mats[2].count == 2, total)
end

print()
print("=== the planner ===")
print()

do
  local bp = B.parse(HUT)
  local steps, floating = P.order(bp)
  test("every block of the hut gets a step", #steps == 27 and #floating == 0, #steps)
  test("the bottom layer goes first", steps[1][2] == 1 and steps[15][2] == 1 and steps[16][2] == 2)
  local jumps = 0
  for i = 2, 15 do
    local a, b = steps[i - 1], steps[i]
    if math.abs(a[1] - b[1]) + math.abs(a[3] - b[3]) > 1 then jumps = jumps + 1 end
  end
  test("a layer is swept back and forth, with no walking back", jumps == 0, jumps)
  test("moves come from walking the order", P.moves({ { 1, 1, 1, "a" }, { 3, 1, 1, "a" } }) == 2)
end

do
  local bp = B.new(3, 3, 1)
  B.addBlock(bp, "a", "m:a", 0, "A")
  B.set(bp, 1, 1, 1, "a")
  B.set(bp, 1, 2, 1, "a")
  B.set(bp, 2, 2, 1, "a")           -- hung off the wall
  B.set(bp, 3, 3, 1, "a")           -- touches nothing below or beside
  local steps, floating = P.order(bp)
  test("a block hung off a wall can be placed", #steps == 3)
  test("a block touching nothing is floating", #floating == 1 and floating[1][1] == 3 and floating[1][2] == 3)
  local wrap = B.new(3, 2, 2)
  B.addBlock(wrap, "a", "m:a", 0, "A")
  B.set(wrap, 3, 1, 1, "a")
  B.set(wrap, 1, 2, 2, "a")          -- next in id order to (3,2,1)'s row end
  local _, loose = P.order(wrap)
  test("the end of one row does not touch the start of the next", #loose == 1, #loose)
  local mats = { { count = 65 }, { count = 64 }, { count = 1 } }
  local stacks, trips = P.trips(mats, 2)
  test("stacks and loads", stacks == 4 and trips == 2, stacks .. "," .. trips)
end

-- ── A geolyzer, to the letter of OC 1.8.10 ─────────────────────────────
-- Read from Geolyzer.scan and EventHandlerVanilla.onGeolyzerScan:
--   * all of y, w, d, h or none; at most 64 cells; every corner within 32
--   * the answer is always 64 long, filled with noise first: only the box
--     is written over, so anything past it is NOT zero
--   * air, replaceable blocks and unloaded chunks are written as exactly 0
--   * a real block is noise * distance * 2 + hardness, noise in +-1/33
--   * one charge a call, however big
local function geolyzer(world, opts)
  opts = opts or {}
  local g = { calls = 0, energy = opts.energy or math.huge, spent = 0 }
  local seed = 12345
  local function byte()
    seed = (seed * 1103515245 + 12345) % 2147483648
    return (seed >> 16) % 256 - 128
  end
  function g.scan(x, z, y, w, d, h)
    if not (y and w and d and h) then error("the fake only takes all six") end
    if w * d * h > 64 then error("volume too large (maximum is 64)") end
    local maxX, maxY, maxZ = x + w - 1, y + h - 1, z + d - 1
    for _, n in ipairs({ x, y, z, maxX, maxY, maxZ }) do
      if math.abs(n) > 32 then error("location out of bounds") end
    end
    if g.energy < 10 then return nil, "not enough energy" end
    g.energy = g.energy - 10
    g.spent = g.spent + 10
    g.calls = g.calls + 1
    local data = {}
    for i = 1, 64 do data[i] = byte() / 128 / 33 end
    for ry = y, maxY do
      for rz = z, maxZ do
        for rx = x, maxX do
          local i = (rx - x) + ((rz - z) + (ry - y) * d) * w
          local hard = world(rx, ry, rz)
          if hard == nil then data[i + 1] = 0.0
          else data[i + 1] = data[i + 1] * math.sqrt(rx * rx + ry * ry + rz * rz) * 2 + hard end
        end
      end
    end
    return data
  end
  return g
end

print()
print("=== the survey ===")
print()

do
  test("an empty cell is read as air, whatever the distance", G.classify(0, 50) == G.AIR)
  test("a soft block far away is still there", G.classify(0.01, 50) == G.SOLID)
  test("a noisy reading below zero far away is a block, not bedrock", G.classify(-1.5, 50) == G.SOLID)
  test("bedrock close to is bedrock", G.classify(-1, 3) == G.FIXED)
  test("water stands clear of the noise at the far corner", G.classify(100 - 55 * G.NOISE, 55) == G.LIQUID)
  test("obsidian is not water at the far corner", G.classify(50 + 55 * G.NOISE, 55) == G.SOLID)
  test("4x4x4 cubes: a call's 64 cells used in full", G.calls(4, 4, 4) == 1 and G.calls(9, 7, 25) == 3 * 2 * 7)
  test("a site past the range is refused", G.check({ x = 30, z = 0, y = 0, w = 9, d = 1, h = 1 }) ~= nil)
  test("a height past the range is refused", G.check({ x = 0, z = 0, y = -40, w = 1, d = 1, h = 1 }) ~= nil)
  test("the edge of the range is fine", G.check({ x = -32, z = -32, y = -32, w = 65, d = 65, h = 65 }) == nil)
end

-- A site: grass at y -1 (hardness 0.6), stone under it, a pond, a tree,
-- a pit, and tall grass that a scan cannot see.
local function world(x, y, z)
  if x == 2 and z == 2 and y >= 0 and y <= 3 then return 2 end        -- a trunk
  if x >= 1 and x <= 3 and z >= 1 and z <= 3 and y >= 3 and y <= 4 then return 0.2 end  -- its leaves
  if x == -3 and z == -2 then                                         -- a pond
    if y == -1 then return 100 end
    if y == -2 then return 0.6 end
  end
  if x == -1 and z == 2 and y >= -3 and y <= -1 then return nil end   -- a pit
  if y == -1 then return 0.6 end
  if y < -1 then return 1.5 end
  return nil
end

do
  local g = geolyzer(world)
  local box = { x = -4, z = -3, y = -8, w = 9, d = 7, h = 25 }
  local site, err = G.survey(g.scan, box)
  test("a survey runs", site ~= nil, err)
  test("...in the calls it said it would", g.calls == G.calls(9, 7, 25) and site.calls == g.calls, g.calls)
  test("...charged by the call", g.spent == g.calls * G.COST)
  local wrong = 0
  for cz = 1, 7 do
    for cx = 1, 9 do
      for y = -8, 16 do
        local want = world(box.x + cx - 1, y, box.z + cz - 1)
        local got = G.at(site, cx, cz, y)
        if (want == nil) ~= (got == G.AIR) then wrong = wrong + 1 end
      end
    end
  end
  test("every one of 1,575 cells reads true, with noise on each block", wrong == 0, wrong)
  test("the pond is liquid", G.at(site, 2, 2, -1) == G.LIQUID)
  local top, kind = G.top(site, 1, 1)
  test("a column's top is its highest block", top == -1 and kind == G.SOLID, top)
  local rows = G.map(site, 0)
  test("flat ground reads ready", rows[1]:sub(1, 1) == ".", rows[1])
  test("the pond shows", rows[2]:sub(2, 2) == "~", rows[2])
  test("the pit shows how far short it is", rows[6]:sub(4, 4) == "c", rows[6])
  test("the tree shows how high it stands", rows[6]:sub(7, 7) == "5", rows[6])

  local levels = G.fit(site, 4)
  test("the best floor sits on the ground, tree or no tree", levels[1].y == 0, levels[1].y)
  test("...counting the tree as blocks in the way", levels[1].clear == 4 + 8, levels[1].clear)
  test("...and the pit and the pond as blocks to fill",
    levels[1].fill == 3 + 1, levels[1].fill)
  test("...and the canopy over it as above the building", levels[1].over == 9, levels[1].over)
  test("a thinner building clears less", G.fit(site, 3)[1].clear == 3, G.fit(site, 3)[1].clear)
  test("a band with no room for the building has no levels", #G.fit(site, 25) == 0)
end

do
  -- A scan may not be read past its box: the tail is noise, not zeros.
  local g = geolyzer(function() return nil end)
  local site = G.survey(g.scan, { x = 0, z = 0, y = 0, w = 1, d = 1, h = 1 })
  test("noise past the end of a small scan is never read as blocks", site and #site.cols[1] == 0)
  local out = g.scan(0, 0, 0, 1, 1, 1)
  test("...and the fake really does put noise there", #out == 64 and out[64] ~= 0)
end

do
  -- A cave costs nothing to clear, and a robot working from above would
  -- have to dig through its roof. The floor stays on the surface, even
  -- with something to clear there.
  local cave = function(x, y, z)
    if y == 0 then return 1.5 end
    if y < 0 and y > -4 then return nil end
    if y <= -4 then return 1.5 end
  end
  local site = G.survey(geolyzer(cave).scan, { x = 0, z = 0, y = -6, w = 2, d = 2, h = 12 })
  test("a cave under the surface does not move the floor", G.fit(site, 3)[1].y == 1, G.fit(site, 3)[1].y)
  local stump = function(x, y, z)
    if x == 0 and z == 0 and y == 1 then return 2 end
    return cave(x, y, z)
  end
  local site2 = G.survey(geolyzer(stump).scan, { x = 0, z = 0, y = -6, w = 2, d = 2, h = 12 })
  test("...not even when the surface has something on it", G.fit(site2, 3)[1].y == 1, G.fit(site2, 3)[1].y)
end

do
  -- Short of power: it waits, and carries on.
  local waits = 0
  local g = geolyzer(function() return nil end, { energy = 10 })
  local site = G.survey(g.scan, { x = 0, z = 0, y = 0, w = 8, d = 4, h = 4 },
    { wait = function() waits = waits + 1; g.energy = g.energy + 10 end })
  test("no power: it waits for more, and finishes", site ~= nil and waits == 1, waits)
  local dead = geolyzer(function() return nil end, { energy = 0 })
  local none, err = G.survey(dead.scan, { x = 0, z = 0, y = 0, w = 1, d = 1, h = 1 }, { wait = function() end })
  test("no power at all stops, and says so", none == nil and tostring(err):find("energy", 1, true) ~= nil, err)
  local _, why = G.survey(function() error("location out of bounds") end, { x = 0, z = 0, y = 0, w = 1, d = 1, h = 1 })
  test("a scan that throws is reported, not raised", tostring(why):find("out of bounds", 1, true) ~= nil, why)
  local _, short = G.survey(function() return {} end, { x = 0, z = 0, y = 0, w = 1, d = 1, h = 1 })
  test("a short answer is refused", short == "a scan came back short", short)
  local _, cut = G.survey(function() return nil, "scan was canceled" end, { x = 0, z = 0, y = 0, w = 1, d = 1, h = 1 })
  test("a canceled scan says so, without waiting for power", cut == "scan was canceled", cut)
end

-- ── The real init.lua, on a GPU that remembers ─────────────────────────
print()
print("=== the designer ===")
print()

local function chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

local function machine(opts)
  opts = opts or {}
  local W, H = opts.W or 80, opts.H or 25
  local fx = { files = opts.files or {}, out = {}, screens = {} }
  local grid = {}
  for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = " " end end
  function fx.text()
    local t = {}
    for y = 1, H do t[y] = table.concat(grid[y]) end
    return table.concat(t, "\n")
  end
  local gpu = {
    getResolution = function() return W, H end,
    getDepth = function() return opts.depth or 8 end,
    setForeground = function() end, setBackground = function() end,
    set = function(x, y, s)
      for i, ch in ipairs(chars(s)) do
        if grid[y] and grid[y][x + i - 1] then grid[y][x + i - 1] = ch end
      end
    end,
    fill = function(x, y, w, h, ch)
      for yy = y, y + h - 1 do
        for xx = x, x + w - 1 do
          if grid[yy] and grid[yy][xx] then grid[yy][xx] = ch end
        end
      end
    end,
  }
  local component = {
    list = function(kind)
      local done = false
      return function()
        if done or (kind ~= "gpu" and not (kind == "geolyzer" and opts.geolyzer)) then return nil end
        done = true
        return kind .. "-1", kind
      end
    end,
    proxy = function(addr)
      if addr == "geolyzer-1" then return opts.geolyzer end
      return gpu
    end,
  }
  local queue = {}
  for _, e in ipairs(opts.keys or {}) do queue[#queue + 1] = e end
  local computer = {
    uptime = function() return 0 end,
    pullSignal = function()
      fx.screens[#fx.screens + 1] = fx.text()
      local e = table.remove(queue, 1)
      if e then return table.unpack(e) end
      return "interrupted"
    end,
  }
  local fs = {
    exists = function(p) return fx.files[p] ~= nil end,
    readFile = function(p) return fx.files[p] end,
    writeFile = function(p, d)
      if opts.writeError then error(opts.writeError, 0) end
      fx.files[p] = d
      return true
    end,
  }
  local function req(name)
    if name == "component" then return component end
    if name == "computer" then return computer end
    if name == "shell.keys" and opts.quitLabel then
      return { is = function(_, c) return c == 17 end, label = function() return opts.quitLabel end }
    end
    if name:sub(1, 7) == "prefab." then return require(name) end
    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
  local env = setmetatable({ require = req, fs = fs }, { __index = _G })
  local main = assert(loadfile("modules/prefab/init.lua", "t", env))()
  fx.V = main.text
  fx.run = function(args)
    fx.out = {}
    main.commands.prefab(args, function(t) fx.out[#fx.out + 1] = tostring(t) end)
    return table.concat(fx.out, "\n")
  end
  return fx
end

local function key(code, ch) return { "key_down", "kbd", ch or 0, code } end
local function char(c) return key(0, c:byte()) end
local function typed(s) local t = {} for c in s:gmatch(".") do t[#t + 1] = char(c) end return t end
local QUIT, ENTER = key(16, 17), key(28, 13)
local LEFT, RIGHT, UP, DOWN = key(203), key(205), key(200), key(208)
local PGUP, PGDN, DEL, TAB = key(201), key(209), key(211), key(15, 9)
local SPACE = char(" ")
local function script(...)
  local out = {}
  for _, part in ipairs({ ... }) do
    if type(part[1]) == "string" then out[#out + 1] = part
    else for _, k in ipairs(part) do out[#out + 1] = k end end
  end
  return out
end
local function has(s, n) return s ~= nil and s:find(n, 1, true) ~= nil end
local function first(fx, n) for _, s in ipairs(fx.screens) do if s:find(n, 1, true) then return s end end end

do
  local fx = machine({ keys = { QUIT }, quitLabel = "^Q / F10" })
  local ok, err = pcall(fx.run, {})
  test("a bare `prefab` opens", ok, err)
  local s = fx.screens[1]
  test("the header says what it is looking at", has(s, "PREFAB  Untitled") and has(s, "Y plan, slice 1/8"))
  test("the blocks are listed", has(s, "Cobblestone") and has(s, "Glass"))
  test("the key bar ends on the way out", has(s, "^Q / F10 Quit"))
  test("the box has edges", has(s, ". . ."))
  test("every key can be found: the view and the way out on the bar",
    has(s, "XYZ View") and has(s, "PgUp/Dn Slice"))
  test("...and the rest beside the grid", has(s, "R Rect") and has(s, "S Save") and has(s, "M Report"))
end

do
  -- Draw on two layers, save, and read the file the way anyone would.
  local keys = script(
    { SPACE, RIGHT, SPACE, RIGHT, char("2"), SPACE },   -- a, a, then planks
    { DOWN, DEL },                                      -- erase an empty cell
    { PGUP, char("3"), SPACE },                         -- up a layer, glass
    { char("s") }, typed("/hut.bp"), { ENTER },
    { QUIT })
  local fx = machine({ keys = keys })
  local ok, err = pcall(fx.run, { "new", "4", "2", "3", "My", "hut" })
  test("a session of keys runs", ok, err)
  test("`new` takes a size and a name", has(fx.screens[1], "PREFAB  My hut") and has(fx.screens[1], "slice 1/2"))
  local bp, perr = B.parse(fx.files["/hut.bp"] or "")
  test("what it saved parses", bp ~= nil, perr)
  test("the blocks landed where they were put", bp and B.get(bp, 1, 1, 1) == "a" and B.get(bp, 2, 1, 1) == "a"
    and B.get(bp, 3, 1, 1) == "b", bp and B.serialize(bp))
  test("PgUp went up a layer", bp and B.get(bp, 3, 2, 2) == "c", bp and B.serialize(bp))
  test("the slice under the one being drawn shows faintly", has(first(fx, "slice 2/2"), "a a"))
  test("a saved blueprint leaves without asking", not has(fx.screens[#fx.screens], "Leave without saving"))
end

do
  -- A front view: the bottom row of the screen is the ground.
  local keys = script({ char("z") }, { DOWN, DOWN, SPACE }, { char("s") }, typed("/f.bp"), { ENTER }, { QUIT })
  local fx = machine({ keys = keys })
  pcall(fx.run, { "new", "3", "3", "3" })
  local bp = B.parse(fx.files["/f.bp"] or "")
  test("Z looks from the front", has(fx.screens[2], "Z front, slice 1/3"))
  test("a block at the bottom of a front view is on the ground", bp and B.get(bp, 1, 1, 1) == "a")
end

do
  -- A rectangle, undo, and the report.
  local keys = script({ char("r"), RIGHT, RIGHT, DOWN, char("r") }, { char("m") }, { SPACE },
    { char("u") }, { char("m") }, { SPACE }, { char("s") }, typed("/r.bp"), { ENTER }, { QUIT })
  local fx = machine({ keys = keys })
  pcall(fx.run, { "new", "4", "2", "3" })
  local s = first(fx, "What this takes")
  test("R fills a rectangle, as the report counts", has(s, "6  Cobblestone"), s)
  test("the report says what it takes", has(s, "1 stack(s): 1 load(s) for a 16-slot robot"))
  test("the box has its frame", has(s, "╔") and has(s, "╡ What this takes ╞"))
  local bp = B.parse(fx.files["/r.bp"] or "")
  test("U takes the whole rectangle back", bp and next(bp.cells) == nil)
  test("a pop-up leaves nothing behind", not has(fx.screens[#fx.screens], "═"))
end

do
  -- Copy a layer up, the way a wall gets built.
  local keys = script({ SPACE, RIGHT, SPACE }, { char("c") }, { PGUP }, { char("v") },
    { char("s") }, typed("/c.bp"), { ENTER }, { QUIT })
  local fx = machine({ keys = keys })
  pcall(fx.run, { "new", "3", "2", "2" })
  local bp = B.parse(fx.files["/c.bp"] or "")
  test("C and V copy a slice up", bp and B.get(bp, 2, 2, 1) == "a" and B.get(bp, 1, 2, 1) == "a")
end

do
  -- The mouse paints; the right button erases; the list picks a block.
  local keys = {
    { "touch", "scr", 5, 3, 0, "p" },        -- cell 3,1
    { "drag", "scr", 7, 3, 0, "p" },         -- and on to cell 4,1
    { "touch", "scr", 5, 3, 1, "p" },        -- right button: erases 3,1
    { "touch", "scr", 70, 5, 0, "p" },       -- second block in the list
    { "touch", "scr", 1, 4, 0, "p" },        -- cell 1,2, with it
    char("s") }
  for _, k in ipairs(typed("/m.bp")) do keys[#keys + 1] = k end
  keys[#keys + 1] = ENTER
  keys[#keys + 1] = QUIT
  local fx = machine({ keys = keys })
  local ok, err = pcall(fx.run, { "new", "5", "1", "3" })
  test("a mouse session runs", ok, err)
  local bp = B.parse(fx.files["/m.bp"] or "")
  test("a click and a drag paint", bp and B.get(bp, 4, 1, 1) == "a", fx.files["/m.bp"])
  test("the right button erases", bp and B.get(bp, 3, 1, 1) == nil)
  test("a click on the list picks a block", bp and B.get(bp, 1, 1, 2) == "b", fx.files["/m.bp"])
end

do
  -- Leaving with work unsaved asks, and N stays.
  local keys = script({ SPACE }, { QUIT }, { char("n") }, { char("y") }, { QUIT }, { char("y") })
  local fx = machine({ keys = keys })
  pcall(fx.run, { "new", "3", "2", "2" })
  test("leaving with work unsaved asks", first(fx, "Leave without saving?") ~= nil)
end

do
  -- A big box scrolls to keep the cursor in view.
  local keys = {}
  for _ = 1, 40 do keys[#keys + 1] = RIGHT end
  keys[#keys + 1] = QUIT
  local fx = machine({ keys = keys })
  local ok, err = pcall(fx.run, { "new", "64", "2", "64" })
  test("a box wider than the screen runs", ok, err)
  local s = fx.screens[#fx.screens]
  test("the cursor stays on screen", has(s, "At 41,1,1"), s and s:sub(1, 300))
end

do
  -- Blocks of your own.
  local keys = script({ char("a") }, typed("mymod:copper_block"), { ENTER }, typed("Copper"), { ENTER },
    typed("3"), { ENTER }, { SPACE }, { char("s") }, typed("/k.bp"), { ENTER }, { QUIT })
  local fx = machine({ keys = keys })
  pcall(fx.run, { "new", "2", "1", "1" })
  local bp = B.parse(fx.files["/k.bp"] or "")
  local p = bp and bp.palette[B.get(bp, 1, 1, 1) or ""]
  test("A adds a block by registry name, label and damage",
    p and p.id == "mymod:copper_block" and p.label == "Copper" and p.meta == 3, fx.files["/k.bp"])
  local bad = script({ char("a") }, typed("nocolon"), { ENTER }, { ENTER }, { ENTER }, { char("x") }, { QUIT })
  local fx2 = machine({ keys = bad })
  pcall(fx2.run, { "new", "2", "1", "1" })
  test("a name that is not one is refused, and says why", first(fx2, "modname:blockname") ~= nil)
end

do
  -- Open and information.
  local fx = machine({ files = { ["/hut.bp"] = HUT }, keys = { QUIT } })
  local out = fx.run({ "info", "/hut.bp" })
  test("info names the build", has(out, "Starter hut: 5x2x3, 27 blocks"), out)
  test("...its materials", has(out, "25  Cobblestone  (minecraft:cobblestone)"))
  test("...and that it can all be placed", has(out, "Every block has something to place against."))
  test("...for the robot asked about", has(fx.run({ "info", "/hut.bp", "1" }), "2 stack(s): 2 load(s) for a 1-slot robot"))
  local ok, err = pcall(fx.run, { "/hut.bp" })
  test("a file opens in the designer", ok, err)
  test("...showing what is in it", has(fx.screens[1], "PREFAB  Starter hut"))
  test("a missing file says so", has(fx.run({ "/nope.bp" }), "no such file"))
  test("no blueprint says so", has(fx.run({ "info" }), "Which blueprint?"))
  test("a bad size says so", has(fx.run({ "new", "0", "1", "1" }), "each side"))
  test("help is there", has(fx.run({ "help" }), "prefab new"))
  local tall = "PREFAB1\nsize 2 3 1\nblock a m:a 0 A\nlayer 1\na.\nlayer 2\n..\nlayer 3\n.a\n"
  local fx2 = machine({ files = { ["/t.bp"] = tall } })
  test("info names what floats, and where", has(fx2.run({ "info", "/t.bp" }), "1 floating: nothing to place against, first at 2,3,1"))
end

do
  -- The survey, through the real command.
  local g = geolyzer(world)
  local fx = machine({ geolyzer = g, files = { ["/hut.bp"] = HUT } })
  local out = fx.run({ "survey", "9", "7", "--height", "4", "--at", "-4", "-3" })
  test("survey says what it is about to spend", has(out, "Reading 9x7x21: 36 scans, about 2 s and 360 energy."), out)
  test("...and spends exactly that", g.calls == 36 and g.spent == 360, g.calls)
  test("survey names the best floor", has(out, "Best floor: Y 0 from the geolyzer"), out)
  test("...and what it costs", has(out, "12 block(s) in the way, 4 to fill under the floor"), out)
  test("...and what is over it", has(out, "9 more above the building"), out)
  test("...and draws the site", has(out, ".~.......") and has(out, "? nothing read"), out)
  local ok, err = pcall(fx.run, { "survey", "/hut.bp" })
  test("a blueprint gives the site its size", ok, err)
  test("...and its height", has(fx.run({ "survey", "/hut.bp" }), "Reading 5x3x19"), fx.run({ "survey", "/hut.bp" }))
  local noGeo = machine({})
  test("no geolyzer says so", has(noGeo.run({ "survey", "9", "7" }), "No geolyzer"))
  test("a site out of range says so before reading anything",
    has(fx.run({ "survey", "9", "7", "--at", "30", "0" }), "past the geolyzer's range"))
  test("a bad option is named", has(fx.run({ "survey", "9", "7", "--zoom" }), "--zoom"))
  test("nothing to survey says what it wants", has(fx.run({ "survey" }), "prefab survey <file.bp>"))
  test("--at wants two numbers", has(fx.run({ "survey", "9", "7", "--at", "1" }), "--at needs"))
  test("a band with no room says what to change",
    has(fx.run({ "survey", "2", "2", "--height", "9", "--up", "2", "--down", "1" }), "too thin"))
  local wet = geolyzer(function(_, y) if y <= 0 then return 100 end end)
  local wetOut = machine({ geolyzer = wet }).run({ "survey", "2", "2", "--height", "2" })
  test("liquid in the way is pointed out", has(wetOut, "liquid"), wetOut)
  local none = geolyzer(function() return nil end)
  local noneOut = machine({ geolyzer = none }).run({ "survey", "2", "2" })
  test("nothing read says it may be an unloaded chunk", has(noneOut, "unloaded chunk"), noneOut)
end

do
  -- Export, through the real command. test_prefab_export.lua runs what it
  -- writes; this is the words around it.
  local fx = machine({ files = { ["/hut.bp"] = HUT } })
  local out = fx.run({ "export", "/hut.bp", "/build.lua", "--slots", "4" })
  test("export writes a program", fx.files["/build.lua"] ~= nil and has(out, "Wrote /build.lua: 27 steps"), out)
  test("...that parses", load(fx.files["/build.lua"] or "") ~= nil)
  test("...and gives the load sheet", has(out, "slot 1") and has(out, "Cobblestone"), out)
  test("...and says where the robot stands", has(out, "corner of the first layer"))
  test("--slots is checked", has(fx.run({ "export", "/hut.bp", "/x.lua", "--slots", "0" }), "1 to 64"))
  local chest = fx.run({ "export", "/hut.bp", "/c.lua", "--chest" })
  test("--chest says what goes in the chest", has(chest, "Put a chest right behind the robot"), chest)
  test("...and what the robot needs", has(chest, "needs an inventory controller"), chest)
  test("...and writes a program that fetches", has(fx.files["/c.lua"], "local CHEST = true"))
  local cleared = fx.run({ "export", "/hut.bp", "/k.lua", "--chest", "--clear" })
  test("--clear says how much, and what it takes", has(cleared, "clears 30 cells first") and has(cleared, "pickaxe"), cleared)
  test("...and where the debris goes", has(cleared, "double chest"), cleared)
  test("--clear without --chest is refused", has(fx.run({ "export", "/hut.bp", "/k.lua", "--clear" }), "add --chest"))
  test("an unknown option is named", has(fx.run({ "export", "/hut.bp", "/x.lua", "--fast" }), "--fast"))
  test("it says what it needs", has(fx.run({ "export", "/hut.bp" }), "prefab export <file.bp>"))
  test("a missing blueprint says so", has(fx.run({ "export", "/no.bp", "/x.lua" }), "no such file"))
  test("too few slots says so", has(fx.run({ "export", "/hut.bp", "/x.lua", "--slots", "1" }), "Cannot export"))
  local tall = "PREFAB1\nsize 2 3 1\nblock a m:a 0 A\nlayer 1\na.\nlayer 2\n..\nlayer 3\n.a\n"
  local fx2 = machine({ files = { ["/t.bp"] = tall } })
  test("a floating block refuses the export", has(fx2.run({ "export", "/t.bp", "/x.lua" }), "float"))
  local fx3 = machine({ files = { ["/hut.bp"] = HUT }, writeError = "disk full" })
  test("a failed write says so", has(fx3.run({ "export", "/hut.bp", "/x.lua" }), "Not saved: disk full"))
end

do
  -- A base, the whole way through.
  local BASE = "PREFABBASE1\nname Outpost\nsize 2 2\npart hall 1 1 0\npart room 1 2 0\n"
  local fx = machine({ files = { ["/o.base"] = BASE } })
  test("parts are listed", has(fx.run({ "parts" }), "hall") and has(fx.run({ "parts" }), "doors N E S W"), fx.run({ "parts" }))
  local wrong = machine({ files = { ["/w.base"] = "PREFABBASE1\nsize 1 2\npart hall 1 1 0\npart room 1 2 2\n" } })
  test("check says what is wrong", has(wrong.run({ "check", "/w.base" }), "has a door S into the wall of the room"), wrong.run({ "check", "/w.base" }))
  local empty = machine({ files = { ["/e.base"] = "PREFABBASE1\nsize 2 2\n" } })
  test("an empty base is not a good one", has(empty.run({ "check", "/e.base" }), "no parts yet"), empty.run({ "check", "/e.base" }))
  local good = machine({ files = { ["/g.base"] = "PREFABBASE1\nname Good\nsize 1 2\npart hall 1 1 0\npart room 1 2 0\n" } })
  test("a good layout is called good", has(good.run({ "check", "/g.base" }), "Good: Nothing wrong: 1 way in"), good.run({ "check", "/g.base" }))
  test("compile writes a blueprint", has(good.run({ "compile", "/g.base", "/g.bp" }), "Wrote /g.bp: 7x5x14"), good.files["/g.bp"])
  test("...that parses", B.parse(good.files["/g.bp"] or "") ~= nil)
  test("a base works where a blueprint does: info", has(good.run({ "info", "/g.base" }), "Good: 7x5x14"), good.run({ "info", "/g.base" }))
  test("...and export", has(good.run({ "export", "/g.base", "/b.lua", "--chest", "--clear" }), "Wrote /b.lua"), good.run({ "export", "/g.base", "/b.lua", "--chest", "--clear" }))
  test("...and what it writes runs", load(good.files["/b.lua"] or "") ~= nil)
  test("a bad size for a base says so", has(fx.run({ "base", "0", "1" }), "1 to 9 tiles"))
  test("compile wants a target", has(good.run({ "compile", "/g.base" }), "prefab compile"))
  test("check wants a file", has(good.run({ "check" }), "Which base?"))
  test("a missing base says so", has(good.run({ "check", "/no.base" }), "no such file"))
end

do
  -- The layout designer, driven by keys.
  local keys = script(
    { SPACE },                              -- hall at 1,1
    { DOWN }, { TAB, TAB, TAB, TAB, TAB, TAB },  -- to room
    { char("r"), char("r") },               -- turn what is in hand, on an empty tile
    { SPACE },                              -- room at 1,2, turned 2: door S
    { char("c") }, { SPACE },
    { char("s") }, typed("/l.base"), { ENTER },
    { QUIT })
  local fx = machine({ keys = keys })
  local ok, err = pcall(fx.run, { "base", "3", "3", "Camp" })
  test("the layout designer runs", ok, err)
  test("it says what it is", has(fx.screens[1], "PREFAB BASE  Camp") and has(fx.screens[1], "3 by 3 tiles"))
  test("it lists the parts", has(fx.screens[1], "hall") and has(fx.screens[1], "cross"))
  test("it shows a part's doors", has(fx.screens[1], "Doors: N S"), fx.screens[1])
  test("a placed part shows on its tile, with door gaps", has(fx.screens[3], "┌─  ─┐"), fx.screens[3])
  test("...and its name", has(fx.screens[3], "hall"))
  local text = fx.files["/l.base"]
  test("it saves a base", text ~= nil and has(text, "part hall 1 1 0") and has(text, "part room 1 2 2"), text)
  test("the check is one key away", first(fx, "╡ Check ╞") ~= nil)
  test("...and finds what is wrong", has(first(fx, "╡ Check ╞"), "door"), first(fx, "╡ Check ╞"))
end

do
  -- A tile that is taken, removing, and the mouse.
  local keys = {
    SPACE, SPACE,                           -- the second is refused
    DEL,                                    -- gone
    { "touch", "scr", 8, 3, 0, "p" },       -- click tile 2,1: places
    { "touch", "scr", 8, 3, 1, "p" },       -- right click: removes
    { "touch", "scr", 1, 3, 0, "p" },       -- click tile 1,1: places
    char("s") }
  for _, k in ipairs(typed("/m.base")) do keys[#keys + 1] = k end
  keys[#keys + 1] = ENTER
  keys[#keys + 1] = QUIT
  local fx = machine({ keys = keys })
  local ok, err = pcall(fx.run, { "base", "2", "2" })
  test("keys and the mouse both lay parts", ok, err)
  test("a taken tile is refused, and says how to clear it", first(fx, "Del clears it") ~= nil)
  local text = fx.files["/m.base"] or ""
  test("the right button removes, and the left places", has(text, "part hall 1 1 0") and not has(text, "part hall 2 1"), text)
end

do
  -- A part wider than what is left is refused, not half placed.
  local keys = script({ RIGHT }, { char("a") }, typed("/nope.bp"), { ENTER }, { QUIT })
  local fx = machine({ keys = keys })
  pcall(fx.run, { "base", "2", "2" })
  test("a part file that is not there says so", first(fx, "cannot read /nope.bp") ~= nil)
  local tall = {}
  for _ = 1, 10 do tall[#tall + 1] = TAB end
  local big = script(tall, { SPACE }, { QUIT })
  local fx2 = machine({ keys = big })
  pcall(fx2.run, { "base", "1", "1" })
  test("a part too big for the base is refused", first(fx2, "runs off the base") ~= nil, fx2.screens[#fx2.screens])
  local mono = machine({ depth = 1, W = 50, H = 16, keys = { SPACE, QUIT, char("y") } })
  local ok, err = pcall(mono.run, { "base", "4", "4" })
  test("tier 1 at its smallest runs", ok, err)
  test("...drawing plain characters", not has(mono.screens[#mono.screens - 1] or "", "┌"))
end

do
  -- A failed save says so, and keeps the work.
  local keys = script({ SPACE }, { char("s") }, typed("/x.bp"), { ENTER }, { QUIT }, { char("y") })
  local fx = machine({ keys = keys, writeError = "disk full" })
  pcall(fx.run, { "new", "2", "1", "1" })
  test("a failed save says so", first(fx, "NOT saved: disk full") ~= nil)
  test("the first letter typed replaces a suggested name", first(fx, "/x.bp_") ~= nil
    and first(fx, "untitled.bp/") == nil)
  test("...and quitting still asks", first(fx, "Leave without saving?") ~= nil)
end

do
  local fx = machine({ W = 40, H = 10, keys = { QUIT } })
  test("too small a screen says so", has(fx.run({}), "needs 50x16"))
  local mono = machine({ depth = 1, W = 50, H = 16, keys = { SPACE, QUIT, char("y") } })
  local ok, err = pcall(mono.run, { "new", "4", "2", "3" })
  test("tier 1 at its smallest runs", ok, err)
  test("...with the keys still listed", has(mono.screens[1], "S Save"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
