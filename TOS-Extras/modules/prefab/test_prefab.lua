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
        if done or kind ~= "gpu" then return nil end
        done = true
        return "gpu-1", "gpu"
      end
    end,
    proxy = function() return gpu end,
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
