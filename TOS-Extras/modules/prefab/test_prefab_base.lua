-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: parts, and bases built from them                      ║
-- ║                                                              ║
-- ║  The whole idea rests on one claim: any door meets any door. ║
-- ║  So this lays real parts against each other in every turn    ║
-- ║  and checks a person could walk through, cell by cell, in    ║
-- ║  the compiled blueprint, rather than trusting the check that ║
-- ║  says the doors match.                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/prefab/test_prefab_base.lua   (from the TOS-Extras root)

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
local Parts = require("prefab.parts")
local Base = require("prefab.base")
local Plan = require("prefab.plan")
local T = Parts.TILE

local function has(s, n) return s ~= nil and tostring(s):find(n, 1, true) ~= nil end

print("=== the parts ===")
print()

local WANT = { hall = "N S", gallery = "N S", corner = "N E", tee = "N E S", cross = "N E S W",
               ["end"] = "N", room = "N", sunroom = "N", passage = "N S", hub = "N E S W" }
for _, part in ipairs(Parts.LIBRARY) do
  local doors = Parts.doors(part.bp)
  if WANT[part.name] then
    test(part.name .. " has its doors where it says", Parts.doorText(doors) == WANT[part.name], Parts.doorText(doors))
  end
  test(part.name .. " is whole tiles", Parts.fits(part.bp))
  local _, floating = Plan.order(part.bp)
  test(part.name .. " can be built by a robot", #floating == 0, #floating)
end

do
  -- Every doorway is the same three cells, whichever part it is.
  local same = true
  for _, part in ipairs(Parts.LIBRARY) do
    local d = Parts.doors(part.bp)
    for t in pairs(d.n) do
      local mid = (t - 1) * T
      for off = Parts.DOOR_FROM, Parts.DOOR_TO do
        if B.get(part.bp, mid + off, 3, 1) ~= nil or B.get(part.bp, mid + off, 1, 1) == nil then same = false end
      end
      for y = 2, 4 do
        if B.get(part.bp, mid + 2, y, 1) == nil then same = false end
      end
    end
  end
  test("every north door is 3 wide with a wall each side", same)
  local gallery = Parts.LIBRARY.gallery.bp
  local mats = B.materials(gallery)
  local labels = {}
  for _, m in ipairs(mats) do labels[m.label] = m.count end
  test("windows are glass in the walls", labels.Glass == 2, labels.Glass)
end

do
  local bp = Parts.LIBRARY.corner.bp
  local once = Parts.rotate(bp, 1)
  test("a turn moves the doors with the part", Parts.doorText(Parts.doors(once)) == "E S", Parts.doorText(Parts.doors(once)))
  test("two turns", Parts.doorText(Parts.doors(Parts.rotate(bp, 2))) == "S W")
  test("three turns", Parts.doorText(Parts.doors(Parts.rotate(bp, 3))) == "N W")
  test("four turns are where it began", B.serialize(Parts.rotate(bp, 4)) == B.serialize(bp))
  test("turning one at a time adds up",
    B.serialize(Parts.rotate(Parts.rotate(bp, 1), 1)) == B.serialize(Parts.rotate(bp, 2)))
  local wide = Parts.rotate(B.parse("PREFAB1\nsize 2 1 1\nblock a m:a 0 A\nlayer 1\na.\n"), 1)
  test("a turn swaps width and depth", wide.sx == 1 and wide.sz == 2 and B.get(wide, 1, 1, 1) == "a")
  local great = Parts.doors(Parts.LIBRARY.hall2.bp)
  test("a part two tiles wide has a door on each side, on the tile grid",
    great.n[1] and great.s[2] and great.e[1] and great.w[2], Parts.doorText(great))
  test("...and keeps them turned", Parts.doors(Parts.rotate(Parts.LIBRARY.hall2.bp, 1)).e[1] ~= nil)
end

print()
print("=== laying a base ===")
print()

--- Can someone walk from one cell to another, at head and foot height, in
--- the compiled blueprint? Floor under them, nothing where they stand.
local function walkable(bp, from, to)
  local seen, todo = { [from[1] .. "," .. from[2]] = true }, { from }
  local function free(x, z)
    return B.inside(bp, x, 2, z) and B.get(bp, x, 1, z) ~= nil
      and B.get(bp, x, 2, z) == nil and B.get(bp, x, 3, z) == nil
  end
  while #todo > 0 do
    local c = table.remove(todo)
    if c[1] == to[1] and c[2] == to[2] then return true end
    for _, s in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, nz = c[1] + s[1], c[2] + s[2]
      local k = nx .. "," .. nz
      if not seen[k] and free(nx, nz) then seen[k] = true; todo[#todo + 1] = { nx, nz } end
    end
  end
  return false
end
local function tileMid(x, z) return { (x - 1) * T + 4, (z - 1) * T + 4 } end

do
  -- A room off a hall off a crossroads, the way a base really goes.
  local base = Base.new(3, 3, "Outpost")
  local function put(name, x, z, turns)
    base.parts[#base.parts + 1] = { name = name, x = x, z = z, turns = turns or 0 }
  end
  put("cross", 2, 2)
  put("hall", 2, 1)
  put("room", 3, 2, 3)      -- door N turned to W, facing the crossroads
  put("room", 1, 2, 1)      -- door N turned to E
  put("room", 2, 3)         -- door N, facing up the hall
  local report, err = Base.check(base)
  test("a sensible layout has nothing wrong", report and #report.problems == 0, err or (report and table.concat(report.problems, "; ")))
  test("...and one way in, at the end of the hall", report and report.ways == 1, report and report.ways)
  local bp, cerr = Base.compile(base)
  test("it compiles", bp ~= nil, cerr)
  test("...to 3 tiles by 3", bp.sx == 21 and bp.sz == 21 and bp.sy == 5)
  test("...keeping its name", bp.name == "Outpost")
  for _, to in ipairs({ { 1, 2 }, { 3, 2 }, { 2, 3 }, { 2, 1 } }) do
    test(string.format("you can walk from the crossroads to tile %d,%d", to[1], to[2]),
      walkable(bp, tileMid(2, 2), tileMid(to[1], to[2])))
  end
  test("the compiled base parses back", B.parse(B.serialize(bp)) ~= nil)
  local _, floating = Plan.order(bp)
  test("a robot can build all of it", #floating == 0, #floating)
end

do
  -- Every pair of doors, in every turn that makes them face each other.
  local bad
  for _, a in ipairs(Parts.LIBRARY) do
    for _, b in ipairs(Parts.LIBRARY) do
      if a.w == 1 and b.w == 1 and a.d == 1 and b.d == 1 then
        for ta = 0, 3 do
          for tb = 0, 3 do
            local da = Parts.doors(Parts.rotate(a.bp, ta))
            local db = Parts.doors(Parts.rotate(b.bp, tb))
            if da.e[1] and db.w[1] then
              local base = Base.new(2, 1, "Pair")
              base.parts = { { name = a.name, x = 1, z = 1, turns = ta }, { name = b.name, x = 2, z = 1, turns = tb } }
              local bp = assert(Base.compile(base))
              if not walkable(bp, { 7, 4 }, { 8, 4 }) then bad = a.name .. ta .. "+" .. b.name .. tb end
            end
          end
        end
      end
    end
  end
  test("any door really does meet any door", bad == nil, bad)
end

do
  local base = Base.new(2, 1)
  base.parts = { { name = "corner", x = 1, z = 1, turns = 0 }, { name = "room", x = 2, z = 1, turns = 0 } }
  local r = Base.check(base)
  test("a door into a wall is found", r and has(r.problems[1], "door E into the wall of the room"), r and r.problems[1])
  test("...and so is the room it leaves cut off", r and r.cut == 1, r and r.cut)
  local bp = Base.compile(base)
  test("the walls really do block the way", not walkable(bp, tileMid(1, 1), tileMid(2, 1)))
end

do
  local base = Base.new(1, 2)
  base.parts = { { name = "end", x = 1, z = 2, turns = 0 }, { name = "end", x = 1, z = 1, turns = 2 } }
  local r = Base.check(base)
  test("a base with no door out says so", r and has(table.concat(r.problems, ";"), "no way in"), r and table.concat(r.problems, ";"))
  local two = Base.new(3, 3)
  two.parts = { { name = "hub", x = 1, z = 1, turns = 0 }, { name = "hub", x = 3, z = 3, turns = 0 } }
  test("two parts with a gap between are not joined", Base.check(two).cut == 1)
  test("no parts is said, not called fine", Base.check(Base.new(2, 2)).problems[1] == "This base has no parts yet")
  test("...but cannot be compiled", select(2, Base.compile(Base.new(2, 2))) == "this base has no parts")
end

do
  local function bad(parts, w, d, needle)
    local base = Base.new(w or 2, d or 2)
    base.parts = parts
    local bp, err = Base.compile(base)
    test("refused: " .. needle, bp == nil and has(err, needle), err)
    test("...and by the check too", select(2, Base.check(base)) ~= nil and has(select(2, Base.check(base)), needle))
  end
  bad({ { name = "hall", x = 1, z = 1 }, { name = "room", x = 1, z = 1 } }, 2, 2, "both want tile 1,1")
  bad({ { name = "hall", x = 3, z = 1 } }, 2, 2, "runs off the base")
  bad({ { name = "hall2", x = 2, z = 1 } }, 2, 2, "runs off the base")
  bad({ { name = "nosuch", x = 1, z = 1 } }, 2, 2, "no part called nosuch")
end

do
  -- The base says what things are made of.
  local base = Base.new(1, 1)
  base.parts = { { name = "hub", x = 1, z = 1 } }
  base.blocks.w = { id = "minecraft:obsidian", meta = 0, label = "Obsidian" }
  local mats = B.materials(Base.compile(base))
  local ids = {}
  for _, m in ipairs(mats) do ids[m.id] = m.count end
  test("a base's walls can be anything", ids["minecraft:obsidian"] ~= nil and ids["minecraft:stonebrick"] == nil)
  test("...leaving the rest alone", ids["minecraft:planks"] ~= nil)
end

do
  -- Your own part: a blueprint of whole tiles, its doors found by looking.
  local rows = {}
  for _ = 1, 7 do rows[#rows + 1] = "qqqqqqq" end
  local floor = table.concat(rows, "\n")
  local open = "qqqqqqq\nq.....q\nq.....q\nq.....q\nq.....q\nq.....q\nqq...qq"
  local text = "PREFAB1\nname Workshop\nsize 7 5 7\nblock q minecraft:iron_block 0 Iron\nlayer 1\n" .. floor
    .. "\nlayer 2\n" .. open .. "\nlayer 3\n" .. open .. "\nlayer 4\n" .. open .. "\nlayer 5\n" .. floor .. "\n"
  local files = { ["/home/me/shop.bp"] = text }
  local read = function(p) return files[p] end
  local base = Base.new(1, 2)
  base.parts = { { name = "/home/me/shop.bp", x = 1, z = 1 }, { name = "passage", x = 1, z = 2 } }
  local r = Base.check(base, read)
  test("your own part's door is found by looking", r and #r.problems == 0 and r.ways == 1, r and table.concat(r.problems, ";"))
  local bp, err = Base.compile(base, read)
  test("it compiles in", bp ~= nil, err)
  test("...keeping its own blocks", has(B.serialize(bp), "minecraft:iron_block"))
  test("...and you can walk through", walkable(bp, tileMid(1, 1), tileMid(1, 2)))
  local keys = 0
  for _ in pairs(bp.palette) do keys = keys + 1 end
  test("a block two parts share is one line of the palette", keys == 3 + 1, keys)
  files["/x.bp"] = "PREFAB1\nsize 5 5 7\nblock a m:a 0 A\n"
  local wrong = Base.new(1, 1)
  wrong.parts = { { name = "/x.bp", x = 1, z = 1 } }
  test("a blueprint that is not whole tiles is refused", has(select(2, Base.compile(wrong, read)), "whole tiles"))
  wrong.parts[1].name = "/nope.bp"
  test("a part file that is missing says so", has(select(2, Base.compile(wrong, read)), "cannot read /nope.bp"))
end

print()
print("=== the file ===")
print()

do
  local base = Base.new(3, 2, "Outpost")
  base.parts = { { name = "hall", x = 1, z = 1, turns = 1 }, { name = "/my/part.bp", x = 2, z = 2, turns = 3 } }
  base.blocks.w = { id = "minecraft:obsidian", meta = 0, label = "Obsidian" }
  local text = Base.serialize(base)
  local back, err = Base.parse(text)
  test("a base reads back", back ~= nil, err)
  test("...exactly", back and Base.serialize(back) == text, text)
  test("it is recognised", Base.is(text) and not Base.is("PREFAB1\n"))
  local function bad(t, needle)
    local b, e = Base.parse(t)
    test("refused: " .. needle, b == nil and has(e, needle), e)
  end
  bad("hello", "not a base")
  bad("PREFABBASE1\nname x\n", "no size")
  bad("PREFABBASE1\nsize 99 1\n", "tiles each way")
  bad("PREFABBASE1\npart hall 1 1 0\n", "size comes first")
  bad("PREFABBASE1\nsize 1 1\nblock w nocolon 0 x\n", "modname:blockname")
  bad("PREFABBASE1\nsize 1 1\nnonsense\n", "what is this")
  test("CRLF line ends read the same", Base.parse((text:gsub("\n", "\r\n"))) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
