-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: prefab export, run against a simulated world          ║
-- ║                                                              ║
-- ║  The generated program is loaded and run for real. The world ║
-- ║  under it keeps OpenComputers 1.8.10's rules, from its       ║
-- ║  bytecode and application.conf: move returns nil and a       ║
-- ║  reason, place needs a neighbour of the target cell, a robot ║
-- ║  may only move if its start or target is within 8 of a block ║
-- ║  or beside one, and a robot's right is its own.              ║
-- ║                                                              ║
-- ║  "It generated" proves nothing. What counts here is whether  ║
-- ║  the blocks in the world end up as the blueprint says.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/prefab/test_prefab_export.lua   (from the TOS-Extras root)

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
local E = require("prefab.export")

local HUT = [[
PREFAB1
name Starter hut
size 5 3 3
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
layer 3
aaaaa
aaaaa
aaaaa
]]

-- East, south, west, north: clockwise, as a robot turns.
local DX = { [0] = 1, 0, -1, 0 }
local DZ = { [0] = 0, 1, 0, -1 }

--- A world, a robot in it, and everything the program can touch.
local function world(opts)
  opts = opts or {}
  local W = { cells = {}, moves = 0, turns = 0, said = {}, sleeps = 0, files = opts.files or {},
              blocked = opts.blocked or {}, entity = opts.entity or 0 }
  local ox, oz, f0 = opts.x or 10, opts.z or 20, opts.facing or 0
  local rx, ry, rz, facing = ox, 1, oz, f0
  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  function W.solid(x, y, z)
    if y < 1 then return not (opts.pit and opts.pit[x .. "," .. z]) end
    return W.cells[key(x, y, z)] ~= nil or W.blocked[key(x, y, z)] == true
  end
  --- Blueprint cell to world cell: ahead and to the right of how it stood.
  function W.toWorld(bx, by, bz)
    local a, b = bx - 1, bz - 1
    local right = (f0 + 1) % 4
    return ox + a * DX[f0] + b * DX[right], by, oz + a * DZ[f0] + b * DZ[right]
  end
  function W.block(x, y, z) return W.cells[key(x, y, z)] end
  function W.pos() return rx, ry, rz end

  local slots = {}
  for i = 1, opts.size or 16 do slots[i] = false end
  W.slots = slots
  function W.give(slot, name, damage, n) slots[slot] = { name = name, damage = damage or 0, size = n } end

  -- A chest right behind where the robot started, as a list of stacks.
  W.chest = opts.chest
  local cx, cz = ox - DX[f0], oz - DZ[f0]
  if opts.chest then W.blocked[key(cx, 1, cz)] = true end
  local function overChest() return W.chest and rx == cx and ry == 2 and rz == cz end
  function W.chestHolds(name)
    local n = 0
    for _, st in pairs(W.chest) do if st and st.name == name then n = n + st.size end end
    return n
  end

  local selected = 1
  local energy = opts.energy or math.huge
  W.power = function(e) energy = e end

  local function valid(x, y, z)
    if opts.hover then return true end
    if W.solid(x - 1, y, z) or W.solid(x + 1, y, z) or W.solid(x, y, z - 1) or W.solid(x, y, z + 1)
       or W.solid(x, y + 1, z) then return true end
    for d = 1, 9 do if W.solid(x, y - d, z) then return true end end
    return false
  end

  local robot = {}
  function robot.move(side)
    local dx, dy, dz = 0, 0, 0
    if side == 3 then dx, dz = DX[facing], DZ[facing]
    elseif side == 2 then dx, dz = -DX[facing], -DZ[facing]
    elseif side == 1 then dy = 1
    elseif side == 0 then dy = -1
    else error("bad side") end
    local tx, ty, tz = rx + dx, ry + dy, rz + dz
    if W.entity > 0 then W.entity = W.entity - 1; return nil, "entity" end
    if W.solid(tx, ty, tz) then return nil, "solid" end
    if energy < 15 then return nil, "not enough energy" end
    energy = energy - 15
    if dy >= 0 and not valid(rx, ry, rz) and not valid(tx, ty, tz) then return nil, "impossible move" end
    rx, ry, rz = tx, ty, tz
    W.moves = W.moves + 1
    return true
  end
  function robot.turn(clockwise)
    facing = (facing + (clockwise and 1 or -1)) % 4
    W.turns = W.turns + 1
    return true
  end
  function robot.select(s)
    if s < 1 or s > #slots then error("invalid slot") end
    selected = s
    return s
  end
  function robot.count(s)
    local it = slots[s or selected]
    return it and it.size or 0
  end
  function robot.inventorySize() return #slots end
  function robot.space(s)
    local it = slots[s or selected]
    return it and ((it.maxSize or 64) - it.size) or 64
  end
  function robot.drop(side)
    if side ~= 0 or not overChest() then return false end
    local it = slots[selected]
    if not it then return false end
    W.chest[#W.chest + 1] = it
    slots[selected] = false
    return true
  end
  function robot.detect(side)
    if side ~= 0 then error("only down in this sim") end
    if W.solid(rx, ry - 1, rz) then return true, "solid" end
    return false, "air"
  end
  function robot.place(side)
    if side ~= 0 then error("only down in this sim") end
    local it = slots[selected]
    if not it then return false, "nothing selected" end
    local x, y, z = rx, ry - 1, rz
    if W.solid(x, y, z) then return false end
    -- A neighbour of the target to click on, the robot's own cell aside.
    if not (W.solid(x - 1, y, z) or W.solid(x + 1, y, z) or W.solid(x, y, z - 1)
            or W.solid(x, y, z + 1) or W.solid(x, y - 1, z)) then return false end
    W.cells[key(x, y, z)] = it.name .. "/" .. it.damage
    it.size = it.size - 1
    if it.size == 0 then slots[selected] = false end
    return true
  end

  local ic = { getStackInInternalSlot = function(s)
    local it = slots[s]
    return it and { name = it.name, damage = it.damage, size = it.size } or nil
  end }
  function ic.getInventorySize(side)
    if side ~= 0 or not overChest() then return nil, "no inventory" end
    return math.max(27, #W.chest)
  end
  function ic.getStackInSlot(side, s)
    if side ~= 0 or not overChest() then return nil end
    local st = W.chest[s]
    return st and { name = st.name, damage = st.damage, size = st.size, maxSize = st.maxSize or 64 } or nil
  end
  function ic.suckFromSlot(side, s, n)
    if side ~= 0 or not overChest() then return false end
    local st, it = W.chest[s], slots[selected]
    if not st then return false end
    if it and (it.name ~= st.name or it.damage ~= st.damage) then return false end
    local max = st.maxSize or 64
    local have = it and it.size or 0
    local take = math.min(n or 64, st.size, max - have)
    if take <= 0 then return false end
    slots[selected] = { name = st.name, damage = st.damage, size = have + take, maxSize = st.maxSize }
    st.size = st.size - take
    if st.size == 0 then W.chest[s] = false end
    return true
  end

  local component = { robot = robot,
    isAvailable = function(n)
      if n == "robot" then return opts.noRobot ~= true end
      if n == "inventory_controller" then return opts.ic == true end
      return false
    end,
    inventory_controller = ic }

  local fakeIo = {
    stderr = { write = function(_, s) W.said[#W.said + 1] = s end },
    open = function(p, mode)
      if mode == "r" then
        local data = W.files[p]
        if not data then return nil end
        local pos = 1
        return {
          read = function()
            local nl = data:find("\n", pos, true)
            if not nl then return nil end
            local l = data:sub(pos, nl - 1)
            pos = nl + 1
            return l
          end,
          close = function() end,
        }
      end
      local buf = {}
      return {
        write = function(self, ...)
          for _, v in ipairs({ ... }) do buf[#buf + 1] = tostring(v) end
          return self
        end,
        close = function() W.files[p] = table.concat(buf) end,
      }
    end,
  }

  local env = setmetatable({
    require = function(n)
      if n == "component" then return component end
      if n == "computer" then return { beep = function() end } end
      error("the robot has no " .. n)
    end,
    print = function(s) W.said[#W.said + 1] = tostring(s) end,
    io = fakeIo,
    os = {
      sleep = function()
        W.sleeps = W.sleeps + 1
        if W.onSleep then W.onSleep() end
        if W.sleeps > 2000 then error("the program never stopped waiting", 0) end
      end,
      remove = function(p) W.files[p] = nil end,
    },
  }, { __index = _G })

  function W.run(src, ...)
    local fn, err = load(src, "=build", "t", env)
    if not fn then return false, "does not parse: " .. tostring(err) end
    return pcall(fn, ...)
  end
  function W.text() return table.concat(W.said, "\n") end
  return W
end

--- Fill the robot as the load sheet says.
local function load_up(W, bp, opts)
  local mats = B.materials(bp)
  local map = E.slots(mats, opts and opts.slots or 16)
  for _, m in ipairs(mats) do
    local left = m.count
    for _, s in ipairs(map[m.key]) do
      local n = math.min(64, left)
      if n > 0 then W.give(s, m.id, m.meta, n) end
      left = left - n
    end
  end
end

--- Is the world exactly the blueprint? Returns nil, or the first difference.
local function differs(W, bp)
  for y = 1, bp.sy do
    for z = 1, bp.sz do
      for x = 1, bp.sx do
        local ch = B.get(bp, x, y, z)
        local want = ch and (bp.palette[ch].id .. "/" .. bp.palette[ch].meta) or nil
        local got = W.block(W.toWorld(x, y, z))
        if want ~= got then
          return string.format("%d,%d,%d: want %s, got %s", x, y, z, tostring(want), tostring(got))
        end
      end
    end
  end
end

local function has(s, n) return s ~= nil and s:find(n, 1, true) ~= nil end

print("=== the build ===")
print()

do
  local bp = B.parse(HUT)
  local src, info = E.program(bp, { slots = 16 })
  test("a program is generated", src ~= nil, info)
  test("it says what it builds", has(src, "-- Built by prefab from: Starter hut"))
  test("...and what to load", has(src, "--   slot 1: Cobblestone (40)") and has(src, "--   slot 2: Glass (2)"), src:sub(1, 400))

  for facing = 0, 3 do
    local W = world({ facing = facing })
    load_up(W, bp)
    local ok, err = W.run(src)
    test("facing " .. facing .. ": it runs", ok, err)
    test("facing " .. facing .. ": the world is the blueprint", differs(W, bp) == nil, differs(W, bp))
    test("facing " .. facing .. ": it costs what the export said",
      W.moves == info.moves and W.turns == info.turns, W.moves .. "/" .. info.moves .. ", " .. W.turns .. "/" .. info.turns)
  end

  local W = world()
  load_up(W, bp)
  W.run(src)
  test("it says when it is done", has(W.text(), "Done: 42 placed, 0 already there."), W.text())
  test("it reports each layer", has(W.text(), "Layer 2 of 3"))
  test("it leaves nothing to carry on from", next(W.files) == nil)
  test("the export's figures add up", info.energy == info.moves * 15 + info.turns * 2.5
    and info.seconds == math.ceil((info.moves + info.turns + 42) * 0.4))
end

do
  -- The widest box: every coordinate survives, including the one whose
  -- character is a backslash.
  local bp = B.new(64, 1, 2, "Long wall")
  B.addBlock(bp, "a", "minecraft:stone", 0, "Stone")
  for x = 1, 64 do B.set(bp, x, 1, 1, "a"); B.set(bp, x, 1, 2, "a") end
  local src = E.program(bp, { slots = 16 })
  local W = world()
  load_up(W, bp)
  local ok, err = W.run(src)
  test("a 64-wide wall runs", ok, err)
  test("...and every coordinate survived the encoding", differs(W, bp) == nil, differs(W, bp))
end

do
  -- Damage is part of what a block is: white wool is not red wool.
  local bp = B.new(2, 1, 1, "Flag")
  B.addBlock(bp, "w", "minecraft:wool", 0, "White")
  B.addBlock(bp, "r", "minecraft:wool", 14, "Red")
  B.set(bp, 1, 1, 1, "w")
  B.set(bp, 2, 1, 1, "r")
  local W = world({ ic = true })
  load_up(W, bp)
  local ok, err = W.run((E.program(bp)))
  test("two colours of one block go in the right places", ok and differs(W, bp) == nil, err or differs(W, bp))
end

print()
print("=== when things go wrong ===")
print()

do
  -- More than the robot can carry: it comes back to the corner and asks.
  local bp = B.new(16, 1, 16, "Slab")
  B.addBlock(bp, "a", "minecraft:stone", 0, "Stone")
  for z = 1, 16 do for x = 1, 16 do B.set(bp, x, 1, z, "a") end end
  local src, info = E.program(bp, { slots = 2 })
  test("256 blocks in 2 slots takes two loads", info.loads == 2, info.loads)
  local W = world({ size = 2 })
  W.give(1, "minecraft:stone", 0, 64)
  W.give(2, "minecraft:stone", 0, 64)
  local atRefill = {}
  W.onSleep = function()
    if W.slots[1] == false and W.slots[2] == false then
      atRefill[#atRefill + 1] = { W.pos() }
      W.give(1, "minecraft:stone", 0, 64)
      W.give(2, "minecraft:stone", 0, 64)
    end
  end
  local ok, err = W.run(src)
  test("it finishes across refills", ok and differs(W, bp) == nil, err or differs(W, bp))
  test("it asked once", #atRefill == 1, #atRefill)
  local ax, _, az = atRefill[1] and atRefill[1][1], nil, atRefill[1] and atRefill[1][3]
  test("...standing at the corner, where a player can reach", ax == 10 and az == 20, tostring(ax) .. "," .. tostring(az))
  test("...and said what it wants", has(W.text(), "Out of Stone: load it into slot(s) 1, 2"), W.text())
end

do
  -- With an inventory controller, the wrong item is noticed.
  local bp = B.parse(HUT)
  local src = E.program(bp, { slots = 16 })
  local W = world({ ic = true })
  load_up(W, bp)
  W.give(2, "minecraft:dirt", 0, 2)
  W.onSleep = function() W.give(2, "minecraft:glass", 0, 2) end
  local ok, err = W.run(src)
  test("the wrong item is refused", ok and has(W.text(), "Wrong item for Glass"), err or W.text())
  test("...and nothing wrong was built", differs(W, bp) == nil, differs(W, bp))
end

do
  -- A tree in the way: it stops, says where, and carries on after.
  local bp = B.parse(HUT)
  local src = E.program(bp)
  local W = world({ blocked = {} })
  W.blocked["13,2,20"] = true          -- on the first row, at walking height
  load_up(W, bp)
  local ok, err = W.run(src)
  test("something in the way ends the run cleanly", ok, err)
  test("...saying why", has(W.text(), "cannot move: solid"), W.text())
  test("...and how to carry on", has(W.text(), "Run this again to carry on from here."))
  test("...and it leaves its place", W.files["/home/.prefab-state"] ~= nil)
  local before = W.moves
  W.blocked = {}
  ok, err = W.run(src)
  test("run again, it carries on", ok and has(W.text(), "Carrying on from step"), err)
  test("...and the world is the blueprint, nothing laid twice", differs(W, bp) == nil, differs(W, bp))
  test("...without going back to the start", W.moves > before)
  test("the place is forgotten once it is done", next(W.files) == nil)
end

do
  local bp = B.parse(HUT)
  local src = E.program(bp)
  local W = world({ files = { ["/home/.prefab-state"] = "Some other house\n3 3 3 0 9 5 0\n" } })
  load_up(W, bp)
  W.run(src)
  test("a place saved by another blueprint is ignored", not has(W.text(), "Carrying on"), W.text())
  test("...and the build starts from the start", differs(W, bp) == nil, differs(W, bp))
  local W2 = world({ files = { ["/home/.prefab-state"] = "Starter hut\n3 3 3 0 9 5 0\n" } })
  load_up(W2, bp)
  W2.run(src, "fresh")
  test("`fresh` throws a saved place away", not has(W2.text(), "Carrying on") and differs(W2, bp) == nil)
  local W3 = world({ files = { ["/home/.prefab-state"] = "Starter hut\nnonsense\n" } })
  load_up(W3, bp)
  W3.run(src)
  test("a garbled place is ignored", differs(W3, bp) == nil, differs(W3, bp))
end

do
  -- A player standing there: it waits rather than giving up.
  local bp = B.parse(HUT)
  local W = world({ entity = 5 })
  load_up(W, bp)
  local ok, err = W.run((E.program(bp)))
  test("someone in the way: it waits", ok and W.sleeps >= 5 and differs(W, bp) == nil, err or W.sleeps)
  local stuck = world({ entity = 1000 })
  load_up(stuck, bp)
  stuck.run((E.program(bp)))
  test("...but not forever", has(stuck.text(), "cannot move: entity"), stuck.text())
end

do
  -- A flat battery: it waits for the charger.
  local bp = B.parse(HUT)
  local W = world({ energy = 150 })
  load_up(W, bp)
  W.onSleep = function() W.power(math.huge) end
  local ok, err = W.run((E.program(bp)))
  test("out of energy: it waits and carries on", ok and differs(W, bp) == nil, err or differs(W, bp))
end

do
  -- Something already there is left alone and counted.
  local bp = B.parse(HUT)
  local W = world()
  W.blocked["11,1,20"] = true
  load_up(W, bp)
  W.run((E.program(bp)))
  test("a block already there is counted, not fought", has(W.text(), "Done: 41 placed, 1 already there."), W.text())
end

do
  -- A gap under the first layer, the one the survey says to fill.
  local bp = B.new(1, 1, 1, "Dot")
  B.addBlock(bp, "a", "minecraft:stone", 0, "Stone")
  B.set(bp, 1, 1, 1, "a")
  local W = world()
  load_up(W, bp)
  local ok = W.run((E.program(bp)))
  test("a single block on the ground is fine", ok and differs(W, bp) == nil)
  -- Two blocks with a space between, and a hole under the second.
  local row = B.new(3, 1, 1, "Row")
  B.addBlock(row, "a", "minecraft:stone", 0, "Stone")
  B.set(row, 1, 1, 1, "a")
  B.set(row, 3, 1, 1, "a")
  local gap = world({ pit = { ["12,20"] = true } })
  load_up(gap, row)
  gap.run((E.program(row)))
  test("a block with nothing under it stops, and says where",
    has(gap.text(), "cannot place at 3,1,1: nothing to place against"), gap.text())
end

do
  -- Tall and open, and only reachable by flying over a void.
  local bp = B.new(6, 12, 1, "Gantry")
  B.addBlock(bp, "a", "minecraft:stone", 0, "Stone")
  for y = 1, 12 do B.set(bp, 1, y, 1, "a"); B.set(bp, 6, y, 1, "a") end
  local src, info = E.program(bp, { slots = 16 })
  test("the export sees the hover problem coming", info.hover ~= nil, tostring(info.hover))
  local W = world()
  load_up(W, bp)
  W.run(src)
  test("...and the robot hits it", has(W.text(), "needs a hover upgrade"), W.text())
  local atStep = W.text():match("Stopped at step (%d+)")
  test("...at the very step the export named", tonumber(atStep) == info.hover, tostring(atStep) .. " vs " .. tostring(info.hover))
  local H = world({ hover = true })
  load_up(H, bp)
  H.run(src)
  test("with a hover upgrade it builds", differs(H, bp) == nil, differs(H, bp))
end

do
  local bp = B.parse(HUT)
  local W = world({ noRobot = true })
  W.run((E.program(bp)))
  test("on a computer it says it wants a robot", has(W.text(), "run it on a robot"), W.text())
  local small = world({ size = 1 })
  small.run((E.program(bp, { slots = 16 })))
  test("too few slots says so before moving", has(small.text(), "needs 2 inventory slots") and small.moves == 0, small.text())
end

print()
print("=== fetching from a chest ===")
print()

local function chestOf(bp, extra)
  local out = {}
  for _, m in ipairs((B.materials(bp))) do
    local left = m.count
    while left > 0 do
      local n = math.min(64, left)
      out[#out + 1] = { name = m.id, damage = m.meta, size = n }
      left = left - n
    end
  end
  for _, st in ipairs(extra or {}) do out[#out + 1] = st end
  return out
end

do
  local bp = B.parse(HUT)
  local src, info = E.program(bp, { chest = true })
  test("the program says where the chest goes", has(src, "Put a chest right behind it"))
  test("...and what goes in it", has(src, "--   40 Cobblestone"))
  test("a hut's worth fits in one trip", info.trips == 1 and info.chest == true, info.trips)
  for facing = 0, 3 do
    local W = world({ facing = facing, ic = true, chest = chestOf(bp) })
    local ok, err = W.run(src)
    test("facing " .. facing .. ": an empty robot and a chest build it", ok and differs(W, bp) == nil, err or differs(W, bp))
    test("facing " .. facing .. ": the route costs what the export said",
      W.moves == info.moves and W.turns == info.turns, W.moves .. "/" .. info.moves .. ", " .. W.turns .. "/" .. info.turns)
  end
  local W = world({ ic = true, chest = chestOf(bp) })
  W.run(src)
  test("the chest gave exactly what the build took",
    W.chestHolds("minecraft:cobblestone") == 0 and W.chestHolds("minecraft:glass") == 0)
  local x, y, z = W.pos()
  test("it finishes parked on the chest", x == 9 and y == 2 and z == 20, x .. "," .. y .. "," .. z)
  test("the robot is left empty", W.slots[1] == false and W.slots[2] == false)
end

do
  -- More than it can carry: as many trips as the export said.
  local bp = B.new(16, 1, 16, "Slab")
  B.addBlock(bp, "a", "minecraft:stone", 0, "Stone")
  for z = 1, 16 do for x = 1, 16 do B.set(bp, x, 1, z, "a") end end
  local src, info = E.program(bp, { slots = 2, chest = true })
  test("256 blocks in 2 slots is 2 trips", info.trips == 2, info.trips)
  local W = world({ size = 2, ic = true, chest = chestOf(bp) })
  local ok, err = W.run(src)
  test("it goes back for more, without being asked", ok and differs(W, bp) == nil, err or differs(W, bp))
  test("...on the route the export counted", W.moves == info.moves and W.turns == info.turns,
    W.moves .. "/" .. info.moves)
end

do
  -- Identity is name and damage. A chest full of near misses is left alone.
  local bp = B.new(2, 1, 1, "Flag")
  B.addBlock(bp, "w", "minecraft:wool", 0, "White")
  B.addBlock(bp, "r", "minecraft:wool", 14, "Red")
  B.set(bp, 1, 1, 1, "w")
  B.set(bp, 2, 1, 1, "r")
  local junk = { { name = "minecraft:wool", damage = 5, size = 64 }, { name = "minecraft:dirt", damage = 0, size = 64 } }
  local W = world({ ic = true, chest = chestOf(bp, junk) })
  local ok, err = W.run((E.program(bp, { chest = true })))
  test("damage tells wool from wool", ok and differs(W, bp) == nil, err or differs(W, bp))
  test("what the build does not need stays in the chest",
    W.chestHolds("minecraft:dirt") == 64 and W.chestHolds("minecraft:wool") == 64)
end

do
  -- The chest runs out: it waits on top of it, and says for what.
  local bp = B.parse(HUT)
  local W = world({ ic = true, chest = { { name = "minecraft:glass", damage = 0, size = 2 },
    { name = "minecraft:cobblestone", damage = 0, size = 10 } } })
  W.onSleep = function()
    if W.chestHolds("minecraft:cobblestone") == 0 then
      W.chest[#W.chest + 1] = { name = "minecraft:cobblestone", damage = 0, size = 30 }
    end
  end
  local ok, err = W.run((E.program(bp, { chest = true })))
  test("a short chest: it waits, then finishes", ok and differs(W, bp) == nil, err or differs(W, bp))
  test("...saying what it wants", has(W.text(), "The chest has no Cobblestone"), W.text())
end

do
  local bp = B.parse(HUT)
  local src = E.program(bp, { chest = true })
  local noIc = world({ chest = chestOf(bp) })
  noIc.run(src)
  test("no inventory controller says so before moving",
    has(noIc.text(), "needs an inventory controller") and noIc.moves == 0, noIc.text())
  local noChest = world({ ic = true })
  noChest.run(src)
  test("no chest says where it goes", has(noChest.text(), "right behind where the robot started"), noChest.text())
end

do
  -- A block already standing: what it did not use goes back.
  local bp = B.parse(HUT)
  local W = world({ ic = true, chest = chestOf(bp) })
  W.blocked["11,1,20"] = true
  W.run((E.program(bp, { chest = true })))
  test("what is left over goes back in the chest", W.chestHolds("minecraft:cobblestone") == 1
    and W.slots[1] == false, W.chestHolds("minecraft:cobblestone"))
end

do
  -- Stopped part way: the blocks it carries are counted, not fetched again.
  local bp = B.parse(HUT)
  local src = E.program(bp, { chest = true })
  local W = world({ ic = true, chest = chestOf(bp) })
  W.blocked["13,2,20"] = true
  W.run(src)
  test("stopped with a load on board", has(W.text(), "cannot move: solid"), W.text())
  W.blocked["13,2,20"] = nil
  local ok, err = W.run(src)
  test("it carries on and finishes", ok and differs(W, bp) == nil, err or differs(W, bp))
  test("...and took no more than the build needed", W.chestHolds("minecraft:cobblestone") == 0
    and W.slots[1] == false and W.slots[2] == false)
end

do
  -- Things that stack to 16: more trips than the export can know about.
  local bp = B.new(40, 1, 1, "Fence")
  B.addBlock(bp, "s", "minecraft:sign", 0, "Sign")
  for x = 1, 40 do B.set(bp, x, 1, 1, "s") end
  local stacks = {}
  for i = 1, 3 do stacks[i] = { name = "minecraft:sign", damage = 0, size = 16, maxSize = 16 } end
  local W = world({ size = 1, ic = true, chest = stacks })
  local ok, err = W.run((E.program(bp, { slots = 1, chest = true })))
  test("a 16-stack block just means more trips", ok and differs(W, bp) == nil, err or differs(W, bp))
end

print()
print("=== refusals ===")
print()

do
  local bp = B.new(2, 3, 1, "Float")
  B.addBlock(bp, "a", "minecraft:stone", 0, "Stone")
  B.set(bp, 1, 1, 1, "a")
  B.set(bp, 2, 3, 1, "a")
  test("a floating block refuses, and says where", has(select(2, E.program(bp)), "first at 2,3,1"))
  test("an empty blueprint refuses", has(select(2, E.program(B.new(2, 2, 2))), "nothing in it"))
  local many = B.new(3, 1, 1)
  for i, c in ipairs({ "a", "b", "c" }) do
    B.addBlock(many, c, "m:b" .. i, 0, c)
    B.set(many, i, 1, 1, c)
  end
  test("more blocks than slots refuses", has(select(2, E.program(many, { slots = 2 })), "uses 3 blocks and the robot has 2"))
end

do
  local m = { { key = "a", count = 130 }, { key = "b", count = 1 } }
  local map, loads = E.slots(m, 16)
  test("slots follow what is needed", #map.a == 3 and #map.b == 1 and loads == 1)
  local map2, loads2 = E.slots(m, 2)
  test("short of slots, every block still gets one", #map2.a == 1 and #map2.b == 1 and loads2 == 3, loads2)
end

print()
print("=== a blueprint is a stranger's text ===")
print()

do
  -- A label built to break out of a string, and one to break out of a
  -- comment with a bare return.
  local evil = '"; os.remove("/init.lua") --'
  local text = "PREFAB1\nname " .. evil .. "\nsize 2 1 1\nblock a m:a 0 " .. evil
    .. "\nblock b m:b 0 x\ros.remove(\"/init.lua\")\nlayer 1\nab\n"
  local bp, err = B.parse(text)
  test("the blueprint parses", bp ~= nil, err)
  local src = E.program(bp)
  local removed = false
  local W = world()
  load_up(W, bp)
  local fn = assert(load(src, "=build", "t", setmetatable({
    os = { remove = function() removed = true end, sleep = function() end },
    require = function() return { isAvailable = function() return false end } end,
    io = { stderr = { write = function() end } },
  }, { __index = _G })))
  fn()
  test("a label cannot become code, in a string or in a comment", removed == false)
  local ok, e2 = W.run(src)
  test("...and it still builds", ok and differs(W, bp) == nil, e2 or differs(W, bp))
  test("a generated program never holds a raw control character in a comment",
    not src:match("%-%-[^\n]*\r"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
