-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: parts to build a base from                          ║
-- ║                                                              ║
-- ║  A part sits on a grid of tiles, 7 by 7 by 5 high, and a     ║
-- ║  doorway is always the middle 3 cells of a tile's edge. That ║
-- ║  one rule is what makes parts fit: any door meets any door.  ║
-- ║                                                              ║
-- ║  A built-in part is only its plan, the cells you can walk    ║
-- ║  in. The walls are whatever touches the plan, and the floor  ║
-- ║  and roof run under and over both. So a new part is a few    ║
-- ║  lines, and every part agrees where its doors are. Your own  ║
-- ║  blueprint is a part too, if its footprint is whole tiles;   ║
-- ║  its doors are found by looking. Pure.                       ║
-- ╚══════════════════════════════════════════════════════════════╝

local B = require("prefab.blueprint")

local P = {}

P.TILE, P.HEIGHT = 7, 5
--- The doorway's cells along a tile's edge, and the cell tested for one.
P.DOOR_FROM, P.DOOR_TO, P.DOOR_MID = 3, 5, 4
--- The height inside a doorway, for testing one.
P.DOOR_Y = 3

--- What each letter in a built-in part is made of, until a base says other.
P.ROLES = {
  { key = "w", id = "minecraft:stonebrick", meta = 0, label = "Stone Bricks", role = "walls" },
  { key = "f", id = "minecraft:planks",     meta = 0, label = "Oak Planks",   role = "floor" },
  { key = "r", id = "minecraft:stone",      meta = 0, label = "Stone",        role = "roof" },
  { key = "g", id = "minecraft:glass",      meta = 0, label = "Glass",        role = "windows" },
}

--- The blueprint of a part, from its plan.
local function blueprintOf(name, tw, td, inside, windows)
  local T = P.TILE
  local sx, sz = tw * T, td * T
  local bp = B.new(sx, P.HEIGHT, sz, name)
  for _, r in ipairs(P.ROLES) do B.addBlock(bp, r.key, r.id, r.meta, r.label) end
  local function open(x, z)
    return x >= 1 and x <= sx and z >= 1 and z <= sz and inside(x, z)
  end
  for z = 1, sz do
    for x = 1, sx do
      local here = open(x, z)
      local near = false
      for dz = -1, 1 do
        for dx = -1, 1 do near = near or open(x + dx, z + dz) end
      end
      if here or near then
        B.set(bp, x, 1, z, "f")
        B.set(bp, x, P.HEIGHT, z, "r")
      end
      if near and not here then
        for y = 2, P.HEIGHT - 1 do B.set(bp, x, y, z, "w") end
        if windows and (x % T == P.DOOR_MID or z % T == P.DOOR_MID) then
          B.set(bp, x, P.DOOR_Y, z, "g")
        end
      end
    end
  end
  return bp
end

--! Carved the first time something asks: the 11 of them hold 75 KB, and most
--! runs of `prefab` are a blueprint that never looks at one.
--- A part from a plan: inside(x, z) says which cells can be walked in.
local function carve(name, label, tw, td, inside, windows)
  return setmetatable({ name = name, label = label, w = tw, d = td }, {
    __index = function(part, key)
      if key ~= "bp" then return nil end
      part.bp = blueprintOf(name, tw, td, inside, windows)
      return part.bp
    end,
  })
end

local function within(v, a, b) return v >= a and v <= b end

--- The hall through a tile: 3 wide, down the middle, N to S.
local function ns(x, z, from, to) return within(x, 3, 5) and within(z, from or 1, to or 7) end
local function ew(x, z, from, to) return within(z, 3, 5) and within(x, from or 1, to or 7) end
--- A room filling a tile, with a door on the named sides.
local function room(doors)
  return function(x, z)
    if within(x, 2, 6) and within(z, 2, 6) then return true end
    return (doors.n and z == 1 and within(x, 3, 5)) or (doors.s and z == 7 and within(x, 3, 5))
      or (doors.w and x == 1 and within(z, 3, 5)) or (doors.e and x == 7 and within(z, 3, 5))
  end
end

local LIBRARY = {
  carve("hall", "Hallway", 1, 1, function(x, z) return ns(x, z) end),
  carve("gallery", "Hallway with windows", 1, 1, function(x, z) return ns(x, z) end, true),
  carve("corner", "Corner", 1, 1, function(x, z) return ns(x, z, 1, 5) or ew(x, z, 3, 7) end),
  carve("tee", "T junction", 1, 1, function(x, z) return ns(x, z) or ew(x, z, 3, 7) end),
  carve("cross", "Crossroads", 1, 1, function(x, z) return ns(x, z) or ew(x, z) end),
  carve("end", "Dead end", 1, 1, function(x, z) return ns(x, z, 1, 5) end),
  carve("room", "Room, one door", 1, 1, room({ n = true })),
  carve("sunroom", "Room with windows", 1, 1, room({ n = true }), true),
  carve("passage", "Room, doors at both ends", 1, 1, room({ n = true, s = true })),
  carve("hub", "Room, four doors", 1, 1, room({ n = true, e = true, s = true, w = true })),
  carve("hall2", "Great hall, 2 by 2 tiles", 2, 2, function(x, z)
    return (within(x, 2, 13) and within(z, 2, 13)) or (z == 1 and within(x, 3, 5))
      or (z == 14 and within(x, 10, 12)) or (x == 14 and within(z, 3, 5)) or (x == 1 and within(z, 10, 12))
  end),
}
for i, part in ipairs(LIBRARY) do LIBRARY[part.name] = part; part.index = i end

--- The built-in parts, in the order to show them.
P.LIBRARY = LIBRARY

--- A blueprint turned clockwise, `turns` quarter turns, as a new blueprint.
--- Doorways stay on the tile grid because tiles are square.
function P.rotate(bp, turns)
  turns = turns % 4
  if turns == 0 then return bp end
  local out = bp
  for _ = 1, turns do
    local src = out
    local nx, nz = src.sz, src.sx
    local r = B.new(nx, src.sy, nz, src.name)
    r.palette, r.order = src.palette, src.order
    for _, c in ipairs(B.each(src)) do
      B.set(r, src.sz - c[3] + 1, c[2], c[1], c[4])
    end
    out = r
  end
  return out
end

--- Is this blueprint's footprint whole tiles?
function P.fits(bp)
  local T = P.TILE
  return bp.sx % T == 0 and bp.sz % T == 0 and bp.sy >= P.DOOR_Y
end

--- The doors of a blueprint, found by looking, so a part you drew needs no
--- declaration: { n = { [tile] = true }, e = ..., s = ..., w = ... }. A door
--- is a walkable gap at the middle of a tile's edge: air at door height over
--- a floor.
function P.doors(bp)
  local T = P.TILE
  local tw, td = math.floor(bp.sx / T), math.floor(bp.sz / T)
  local out = { n = {}, e = {}, s = {}, w = {} }
  local function door(x, z)
    return B.get(bp, x, P.DOOR_Y, z) == nil and B.get(bp, x, 1, z) ~= nil
  end
  for t = 1, tw do
    local mid = (t - 1) * T + P.DOOR_MID
    if door(mid, 1) then out.n[t] = true end
    if door(mid, bp.sz) then out.s[t] = true end
  end
  for t = 1, td do
    local mid = (t - 1) * T + P.DOOR_MID
    if door(1, mid) then out.w[t] = true end
    if door(bp.sx, mid) then out.e[t] = true end
  end
  return out, tw, td
end

--- "N E" for showing a part's doors.
function P.doorText(doors)
  local out = {}
  for _, side in ipairs({ "n", "e", "s", "w" }) do
    if next(doors[side]) then out[#out + 1] = side:upper() end
  end
  return #out > 0 and table.concat(out, " ") or "none"
end

return P
