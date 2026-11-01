-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: what a build takes                                  ║
-- ║                                                              ║
-- ║  A robot stands above a cell and places downward, so a block ║
-- ║  goes in once it has something to place against: the ground, ║
-- ║  the layer below, or a neighbour already down. This works    ║
-- ║  out that order, and what cannot be reached by it. Every     ║
-- ║  figure comes from walking the order, never from a formula   ║
-- ║  over the block count. Pure.                                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local B = require("prefab.blueprint")

local P = {}

--- A stack, for counting trips. Doors and the like stack lower, and the
--- blueprint cannot know which: the trips shown are then too few.
P.STACK = 64

--- The order to place every block in, and the ones with nothing to touch.
--- Layers from the bottom. In a layer, sweeps back and forth take whatever
--- touches something placed, so a row hung off a wall builds outward from
--- the wall. Layer 1 stands on the ground, whatever is under it.
function P.order(bp)
  local placed, steps, floating = {}, {}, {}
  local function id(x, y, z) return (z - 1) * bp.sy * bp.sx + (y - 1) * bp.sx + x end
  --! Through inside(): one past the end of a row is the start of the next
  --! one in `id`, so without it a block at the edge of the box would count
  --! as touching a block on the far side.
  local function at(x, y, z) return B.inside(bp, x, y, z) and placed[id(x, y, z)] end
  local function touches(x, y, z)
    if y == 1 then return true end
    return at(x, y - 1, z) or at(x - 1, y, z) or at(x + 1, y, z)
      or at(x, y, z - 1) or at(x, y, z + 1)
  end
  for y = 1, bp.sy do
    local waiting = {}
    for z = 1, bp.sz do
      local from, to, step = 1, bp.sx, 1
      if z % 2 == 0 then from, to, step = bp.sx, 1, -1 end
      for x = from, to, step do
        local ch = B.get(bp, x, y, z)
        if ch then waiting[#waiting + 1] = { x, y, z, ch } end
      end
    end
    local progress = true
    while progress and #waiting > 0 do
      progress = false
      local still = {}
      for _, c in ipairs(waiting) do
        if touches(c[1], c[2], c[3]) then
          placed[id(c[1], c[2], c[3])] = true
          steps[#steps + 1] = c
          progress = true
        else
          still[#still + 1] = c
        end
      end
      waiting = still
    end
    for _, c in ipairs(waiting) do floating[#floating + 1] = c end
  end
  return steps, floating
end

--- Moves to walk `steps`, from above the first cell's corner: one a block,
--- straight along each axis, standing a block over each target.
function P.moves(steps)
  local n, px, py, pz = 0, 1, 2, 1
  for _, s in ipairs(steps) do
    local x, y, z = s[1], s[2] + 1, s[3]
    n = n + math.abs(x - px) + math.abs(y - py) + math.abs(z - pz)
    px, py, pz = x, y, z
  end
  return n
end

--- Slots the materials fill, and the loads that takes with `slots` of them.
function P.trips(mats, slots)
  local stacks = 0
  for _, m in ipairs(mats) do stacks = stacks + math.ceil(m.count / P.STACK) end
  return stacks, math.ceil(stacks / math.max(1, slots))
end

--- All of it, for the screen and for `prefab info`.
function P.report(bp, slots)
  local steps, floating = P.order(bp)
  local mats, total = B.materials(bp)
  local stacks, trips = P.trips(mats, slots or 16)
  return { materials = mats, total = total, stacks = stacks, trips = trips,
           moves = P.moves(steps), floating = floating, placed = #steps }
end

return P
