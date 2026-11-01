-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: a blueprint as a program for a robot                ║
-- ║                                                              ║
-- ║  One self-contained Lua file: the build order as data, and a ║
-- ║  small builder that only needs OpenOS and component.robot.   ║
-- ║  It goes to the robot on a floppy, so it needs no wireless   ║
-- ║  link, no shared secret, and no machine in range.            ║
-- ║                                                              ║
-- ║  A robot has no compass, so nothing here does: the building  ║
-- ║  goes ahead and to the right of wherever the robot is put,   ║
-- ║  facing whichever way it is put.                             ║
-- ║                                                              ║
-- ║  A blueprint is a stranger's text and this turns it into     ║
-- ║  code that runs on a machine, so every string goes through   ║
-- ║  %q and nothing else from the file reaches the output.       ║
-- ║  Pure: blueprint in, source out.                             ║
-- ╚══════════════════════════════════════════════════════════════╝

local B = require("prefab.blueprint")
local P = require("prefab.plan")

local E = {}

--- From application.conf: seconds a robot action takes, energy a move and a
--- turn. Placing costs its time and next to no energy.
E.DELAY, E.MOVE_ENERGY, E.TURN_ENERGY = 0.4, 15, 2.5
--- How high a robot can stand over a block: limitFlightHeight.
E.FLIGHT = 8

--- Split the robot's slots between the blocks. Every block gets one, then
--- whichever still needs the most gets the next. Returns { key = { slot, .. } }
--- and how many loads the build takes, or nil and why.
function E.slots(mats, total)
  if #mats > total then
    return nil, string.format("this blueprint uses %d blocks and the robot has %d slots", #mats, total)
  end
  local map, left, nextSlot = {}, {}, 1
  for _, m in ipairs(mats) do
    map[m.key] = { nextSlot }
    nextSlot = nextSlot + 1
    left[m.key] = math.ceil(m.count / P.STACK) - 1
  end
  while nextSlot <= total do
    local best
    for _, m in ipairs(mats) do
      if left[m.key] > 0 and (not best or left[m.key] > left[best]) then best = m.key end
    end
    if not best then break end
    local list = map[best]
    list[#list + 1] = nextSlot
    nextSlot = nextSlot + 1
    left[best] = left[best] - 1
  end
  local loads = 1
  for _, m in ipairs(mats) do
    loads = math.max(loads, math.ceil(math.ceil(m.count / P.STACK) / #map[m.key]))
  end
  return map, loads
end

--- Walk the build the way the program will, counting what it costs, and
--- finding the first step a robot without a hover upgrade could not reach.
--- This has to stay the same walk as travel() and restock() in the program
--- below; the tests hold the two to the same counts. With opts.chest, opts.map
--- says which slots each block has, and stacks are taken as P.STACK: blocks
--- that stack lower make more trips than this counts.
function E.walk(bp, steps, opts)
  opts = opts or {}
  local placed = {}
  if opts.chest then placed["0,1,1"] = true end
  local function solid(x, y, z)
    if y < 1 then return true end
    return placed[x .. "," .. y .. "," .. z] == true
  end
  --- A cell a robot may stand in: beside a block, or within reach of one.
  local function valid(x, y, z)
    if solid(x - 1, y, z) or solid(x + 1, y, z) or solid(x, y, z - 1) or solid(x, y, z + 1)
       or solid(x, y + 1, z) then return true end
    for d = 1, E.FLIGHT + 1 do
      if solid(x, y - d, z) then return true end
    end
    return false
  end
  local x, y, z, dir = 1, 1, 1, 0
  local moves, turns, hover, trips = 0, 0, nil, 0
  local n = 0
  local function step(nx, ny, nz)
    -- Going down is always allowed.
    if ny >= y and not hover and not valid(x, y, z) and not valid(nx, ny, nz) then hover = n end
    x, y, z = nx, ny, nz
    moves = moves + 1
  end
  local function face(d)
    local diff = (d - dir) % 4
    turns = turns + (diff == 3 and 1 or diff)
    dir = d
  end
  local function travel(tx, ty, tz)
    while y < ty do step(x, y + 1, z) end
    if x ~= tx then
      face(tx > x and 0 or 2)
      while x ~= tx do step(x + (tx > x and 1 or -1), y, z) end
    end
    if z ~= tz then
      face(tz > z and 1 or 3)
      while z ~= tz do step(x, y, z + (tz > z and 1 or -1)) end
    end
    while y > ty do step(x, y - 1, z) end
  end
  local left, carried = {}, {}
  for _, s in ipairs(steps) do
    left[s[4]] = (left[s[4]] or 0) + 1
    carried[s[4]] = 0
  end
  for i, s in ipairs(steps) do
    n = i
    local k = s[4]
    if opts.chest and carried[k] == 0 then
      travel(0, 2, 1)
      trips = trips + 1
      for key, need in pairs(left) do
        carried[key] = math.min(need, #opts.map[key] * P.STACK)
      end
    end
    travel(s[1], s[2] + 1, s[3])
    placed[s[1] .. "," .. s[2] .. "," .. s[3]] = true
    left[k] = left[k] - 1
    carried[k] = carried[k] - 1
  end
  if opts.chest then travel(0, 2, 1) end
  return moves, turns, hover, trips
end

-- The builder. Everything above "--[[DATA]]" in the output is generated.
local BODY = [==[
local component = require("component")
local computer = require("computer")
if not component.isAvailable("robot") then
  io.stderr:write("This is a robot's program: run it on a robot.\n")
  return
end
local robot = component.robot
local ic = component.isAvailable("inventory_controller") and component.inventory_controller or nil

local DOWN, UP, FRONT = 0, 1, 3
local STATE = "/home/.prefab-state"
local PATIENCE = 30                -- seconds to wait for a way to clear
local STOP = {}                    -- thrown by stop()

-- Where the robot is, in the blueprint's cells: it starts in the corner of
-- the first layer. dir is 0 ahead, 1 right, 2 back, 3 left of how it stood.
local x, y, z, dir, at, placed, there = 1, 1, 1, 0, 1, 0, 0

local function save()
  local f = io.open(STATE, "w")
  if not f then return false end
  f:write(NAME, "\n", x, " ", y, " ", z, " ", dir, " ", at, " ", placed, " ", there, "\n")
  f:close()
  return true
end

local function load_state()
  local f = io.open(STATE, "r")
  if not f then return false end
  local name = f:read("*l")
  local line = f:read("*l")
  f:close()
  if name ~= NAME or not line then return false end
  local a, b, c, d, e, g, h = line:match("^(%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+)$")
  if not a then return false end
  x, y, z, dir, at, placed, there = tonumber(a), tonumber(b), tonumber(c), tonumber(d),
    tonumber(e), tonumber(g), tonumber(h)
  return true
end

local function stop(why)
  print("Stopped at step " .. at .. " of " .. TOTAL .. ": " .. tostring(why))
  if save() then print("Run this again to carry on from here.") end
  computer.beep(200, 0.5)
  error(STOP, 0)
end

--- Move one cell, waiting out a player, a mob, or a flat battery.
local function go(side)
  local waited = 0
  while true do
    local ok, why = robot.move(side)
    if ok then return end
    if why == "impossible move" then
      stop("too high to fly here: this robot needs a hover upgrade")
    end
    if why ~= "already moving" then
      waited = waited + 1
      if waited > PATIENCE then stop("cannot move: " .. tostring(why)) end
      os.sleep(1)
    end
  end
end

local function face(d)
  local diff = (d - dir) % 4
  if diff == 3 then robot.turn(false)
  else for _ = 1, diff do robot.turn(true) end end
  dir = d
end

--- Go to a cell, up first, then along X, then along Z. Everything at a
--- layer's own height is empty until that layer is reached, so this way
--- never meets the building.
local function travel(tx, ty, tz)
  while y < ty do go(UP); y = y + 1 end
  if x ~= tx then
    face(tx > x and 0 or 2)
    while x ~= tx do go(FRONT); x = x + (tx > x and 1 or -1) end
  end
  if z ~= tz then
    face(tz > z and 1 or 3)
    while z ~= tz do go(FRONT); z = z + (tz > z and 1 or -1) end
  end
  while y > ty do go(DOWN); y = y - 1 end
end

local function holds(slot, b)
  if not ic then return true end
  local s = ic.getStackInInternalSlot(slot)
  return s ~= nil and s.name == b[1] and s.damage == b[2]
end

--- Stand over the chest and take what the rest of the build still needs,
--- by name and damage, leaving everything else in it alone. The chest sits
--- behind where the robot started, outside the building, so the way there
--- is clear at any height.
local function restock()
  travel(0, 2, 1)
  local size = ic.getInventorySize(DOWN)
  if not size then stop("no chest under the robot: it goes right behind where the robot started") end
  local want = {}
  for i = at, TOTAL do
    local k = STEPS:sub(i * 4, i * 4)
    want[k] = (want[k] or 0) + 1
  end
  for key, list in pairs(SLOTS) do
    for _, s in ipairs(list) do want[key] = (want[key] or 0) - robot.count(s) end
  end
  for cs = 1, size do
    local st = ic.getStackInSlot(DOWN, cs)
    for key, b in pairs(BLOCKS) do
      if st and st.name == b[1] and st.damage == b[2] then
        local left = st.size
        for _, s in ipairs(SLOTS[key]) do
          if left > 0 and want[key] > 0 and (robot.count(s) == 0 or holds(s, b)) then
            local n = math.min(left, want[key], robot.space(s))
            if n > 0 then
              robot.select(s)
              local before = robot.count(s)
              ic.suckFromSlot(DOWN, cs, n)
              local got = robot.count(s) - before
              left, want[key] = left - got, want[key] - got
            end
          end
        end
      end
    end
  end
end

--- Select a slot holding this block. Out of it, go to the chest if there is
--- one. Otherwise, or if the chest has none either, wait where a player can
--- reach until there is some.
local function take(key)
  local b = BLOCKS[key]
  local told, stocked = false, false
  while true do
    local wrong = false
    for _, slot in ipairs(SLOTS[key]) do
      if robot.count(slot) > 0 then
        if holds(slot, b) then robot.select(slot); return end
        wrong = true
      end
    end
    if CHEST and not wrong and not stocked then
      restock()
      stocked = true
    else
      if not told then
        told = true
        travel(CHEST and 0 or 1, CHEST and 2 or y, 1)
        if wrong then print("Wrong item for " .. b[3] .. " in slot(s) " .. table.concat(SLOTS[key], ", "))
        elseif CHEST then print("The chest has no " .. b[3] .. ": put some in it.")
        else print("Out of " .. b[3] .. ": load it into slot(s) " .. table.concat(SLOTS[key], ", ")) end
        computer.beep(800, 0.3)
      end
      os.sleep(2)
      stocked = false
    end
  end
end

local function put(tx, ty, tz)
  local solid, what = robot.detect(DOWN)
  if solid and what == "solid" then
    there = there + 1              -- something is there already: leave it
    return
  end
  local waited = 0
  while true do
    local ok, why = robot.place(DOWN)
    if ok then placed = placed + 1; return end
    waited = waited + 1
    if waited > 5 then
      stop(string.format("cannot place at %d,%d,%d: %s", tx, ty, tz, tostring(why or "nothing to place against")))
    end
    os.sleep(1)
  end
end

local function main(...)
  if (...) == "fresh" then os.remove(STATE)
  elseif load_state() then print("Carrying on from step " .. at .. " of " .. TOTAL .. ".") end
  if robot.inventorySize() < MAXSLOT then
    stop("this needs " .. MAXSLOT .. " inventory slots and the robot has " .. robot.inventorySize())
  end
  if CHEST and not ic then stop("taking from a chest needs an inventory controller") end
  local layer = nil
  while at <= TOTAL do
    local i = (at - 1) * 4
    local tx, ty, tz = STEPS:byte(i + 1) - 47, STEPS:byte(i + 2) - 47, STEPS:byte(i + 3) - 47
    if ty ~= layer then layer = ty; print("Layer " .. ty .. " of " .. LAYERS) end
    take(STEPS:sub(i + 4, i + 4))
    travel(tx, ty + 1, tz)
    put(tx, ty, tz)
    at = at + 1
  end
  if CHEST then
    -- Back over the chest, and anything left over goes back in it.
    travel(0, 2, 1)
    for _, list in pairs(SLOTS) do
      for _, s in ipairs(list) do
        if robot.count(s) > 0 then robot.select(s); robot.drop(DOWN) end
      end
    end
  end
  os.remove(STATE)
  print(string.format("Done: %d placed, %d already there.", placed, there))
  computer.beep(1000, 0.2)
end

local ok, err = pcall(main, ...)
if not ok and err ~= STOP then error(err, 0) end
]==]

--- One line of text, for a comment in the output: a stray return there
--- would end the comment and leave the rest of the line as code.
local function plain(s) return (tostring(s):gsub("%c", " ")) end

--- The program for a blueprint. opts.slots is the robot's inventory, and
--- opts.chest has it fetch from a chest instead of being loaded by hand.
--- Returns source and a table describing it, or nil and why.
function E.program(bp, opts)
  opts = opts or {}
  local total = opts.slots or 16
  local steps, floating = P.order(bp)
  if #floating > 0 then
    local f = floating[1]
    return nil, string.format("%d block(s) float, first at %d,%d,%d: nothing to place them against",
      #floating, f[1], f[2], f[3])
  end
  if #steps == 0 then return nil, "this blueprint has nothing in it" end
  local mats = B.materials(bp)
  local map, loads = E.slots(mats, total)
  if not map then return nil, loads end

  local encoded = {}
  for i, s in ipairs(steps) do
    encoded[i] = string.char(s[1] + 47, s[2] + 47, s[3] + 47) .. s[4]
  end

  local maxSlot = 0
  local sheet, blocks, slots = {}, {}, {}
  for _, m in ipairs(mats) do
    local list = map[m.key]
    for _, s in ipairs(list) do maxSlot = math.max(maxSlot, s) end
    local from, to = list[1], list[#list]
    sheet[#sheet + 1] = { slots = (from == to) and tostring(from) or (from .. "-" .. to),
                          label = m.label, id = m.id, count = m.count }
    blocks[#blocks + 1] = string.format("  [%q] = { %q, %d, %q },", m.key, m.id, m.meta, m.label)
    slots[#slots + 1] = string.format("  [%q] = { %s },", m.key, table.concat(list, ", "))
  end

  local head = { "-- Built by prefab from: " .. plain(bp.name),
    "-- Stand the robot in the corner of the first layer. The building goes ahead",
    "-- of it and to its right, whichever way it faces." }
  if opts.chest then
    head[#head + 1] = "-- Put a chest right behind it, holding:"
    for _, l in ipairs(sheet) do
      head[#head + 1] = string.format("--   %d %s", l.count, plain(l.label))
    end
  else
    head[#head + 1] = "-- Load it first:"
    for _, l in ipairs(sheet) do
      head[#head + 1] = string.format("--   slot %s: %s (%d)", l.slots, plain(l.label), l.count)
    end
  end
  head[#head + 1] = string.format("local NAME = %q", bp.name)
  head[#head + 1] = "local BLOCKS = {"
  for _, l in ipairs(blocks) do head[#head + 1] = l end
  head[#head + 1] = "}"
  head[#head + 1] = "local SLOTS = {"
  for _, l in ipairs(slots) do head[#head + 1] = l end
  head[#head + 1] = "}"
  head[#head + 1] = string.format("local TOTAL, LAYERS, MAXSLOT = %d, %d, %d", #steps, bp.sy, maxSlot)
  head[#head + 1] = "local CHEST = " .. tostring(opts.chest == true)
  -- x, y, z and the key, a character each.
  head[#head + 1] = string.format("local STEPS = %q", table.concat(encoded))

  local moves, turns, hover, trips = E.walk(bp, steps, { chest = opts.chest, map = map })
  return table.concat(head, "\n") .. "\n--[[DATA]]\n" .. BODY, {
    steps = #steps, moves = moves, turns = turns, hover = hover, loads = loads, sheet = sheet,
    chest = opts.chest == true, trips = trips,
    energy = moves * E.MOVE_ENERGY + turns * E.TURN_ENERGY,
    seconds = math.ceil((moves + turns + #steps) * E.DELAY),
  }
end

return E
