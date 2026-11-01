-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: a base, built from parts                            ║
-- ║                                                              ║
-- ║  A base is a text file saying which part goes on which tile, ║
-- ║  turned which way, and what the walls and floors are made    ║
-- ║  of. It compiles to an ordinary blueprint, so everything     ║
-- ║  that takes a blueprint takes a base: the survey, the robot  ║
-- ║  program, the chest, stock and the printer never know it was ║
-- ║  assembled. Like a blueprint it comes from other people, so  ║
-- ║  it is parsed by hand and never executed. Pure.              ║
-- ╚══════════════════════════════════════════════════════════════╝

local B = require("prefab.blueprint")
local P = require("prefab.parts")

local M = {}

local MAGIC = "PREFABBASE1"
--- Tiles a side: a blueprint's 64 cells, in whole tiles.
M.MAX_TILES = math.floor(B.MAX_SIDE / P.TILE)

function M.is(text) return type(text) == "string" and text:sub(1, #MAGIC) == MAGIC end

function M.new(w, d, name)
  return { name = name or "Untitled base", w = w, d = d, parts = {}, blocks = {} }
end

--- The opposite side, and the tile that way.
local OPPOSITE = { n = "s", s = "n", e = "w", w = "e" }
local STEP = { n = { 0, -1 }, s = { 0, 1 }, e = { 1, 0 }, w = { -1, 0 } }

--- A placed part's blueprint, turned. `read(path)` gives a file for a part
--- of your own, whose name is its path. Returns bp, or nil and why.
function M.resolve(entry, read)
  local part = P.LIBRARY[entry.name]
  local bp
  if part then bp = part.bp
  elseif entry.name:sub(1, 1) == "/" then
    local text = read and read(entry.name)
    if not text then return nil, "cannot read " .. entry.name end
    local err
    bp, err = B.parse(text)
    if not bp then return nil, entry.name .. ": " .. tostring(err) end
    if not P.fits(bp) then
      return nil, string.format("%s is %dx%d: a part is whole tiles of %d", entry.name, bp.sx, bp.sz, P.TILE)
    end
  else
    return nil, "no part called " .. entry.name
  end
  return P.rotate(bp, entry.turns or 0)
end

--- What each tile holds. Returns { "x,z" = { index, doors } }, or nil and why.
local function occupancy(base, read)
  local tiles, bps = {}, {}
  for i, e in ipairs(base.parts) do
    local bp, err = M.resolve(e, read)
    if not bp then return nil, err end
    bps[i] = bp
    local doors, tw, td = P.doors(bp)
    if e.x < 1 or e.z < 1 or e.x + tw - 1 > base.w or e.z + td - 1 > base.d then
      return nil, string.format("%s at %d,%d runs off the base", e.name, e.x, e.z)
    end
    for tz = 0, td - 1 do
      for tx = 0, tw - 1 do
        local k = (e.x + tx) .. "," .. (e.z + tz)
        if tiles[k] then
          return nil, string.format("%s and %s both want tile %s", base.parts[tiles[k].index].name, e.name, k)
        end
        local here = { index = i, doors = {} }
        if tz == 0 and doors.n[tx + 1] then here.doors.n = true end
        if tz == td - 1 and doors.s[tx + 1] then here.doors.s = true end
        if tx == 0 and doors.w[tz + 1] then here.doors.w = true end
        if tx == tw - 1 and doors.e[tz + 1] then here.doors.e = true end
        tiles[k] = here
      end
    end
  end
  return tiles, bps
end

--- What each tile holds, for drawing: "x,z" = { index, doors }, or nil and why.
function M.tiles(base, read) return occupancy(base, read) end

--- "2 ways in" for a report that is clean.
function M.summary(report)
  local n = report.ways
  return string.format("Nothing wrong: %d way%s in, and everything is joined up.", n, n == 1 and "" or "s")
end

--- What is wrong with a layout, and what is merely worth knowing.
--- Returns a report { problems = { text, ... }, ways = n, cut = n }, or nil
--- and why, when it cannot even be laid out. A door with nothing past it is a
--- way in, not a fault: a base needs at least one.
function M.check(base, read)
  local tiles, err = occupancy(base, read)
  if not tiles then return nil, err end
  if #base.parts == 0 then return { problems = { "This base has no parts yet" }, ways = 0, cut = 0 } end
  local problems, ways = {}, 0
  local links = {}                       -- part index -> set of part indices
  for i = 1, #base.parts do links[i] = {} end
  local keys = {}
  for k in pairs(tiles) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local t = tiles[k]
    local x, z = k:match("^(%d+),(%d+)$")
    x, z = tonumber(x), tonumber(z)
    for _, side in ipairs({ "n", "e", "s", "w" }) do
      if t.doors[side] then
        local nk = (x + STEP[side][1]) .. "," .. (z + STEP[side][2])
        local other = tiles[nk]
        if not other then
          ways = ways + 1
        elseif other.doors[OPPOSITE[side]] then
          links[t.index][other.index] = true
        else
          problems[#problems + 1] = string.format("The %s at %s has a door %s into the wall of the %s",
            base.parts[t.index].name, k, side:upper(), base.parts[other.index].name)
        end
      end
    end
  end
  -- Everything joined to the first part, door by door.
  local cut = 0
  if #base.parts > 0 then
    local seen, todo = { [1] = true }, { 1 }
    while #todo > 0 do
      local i = table.remove(todo)
      for j in pairs(links[i]) do
        if not seen[j] then seen[j] = true; todo[#todo + 1] = j end
      end
    end
    for i, e in ipairs(base.parts) do
      if not seen[i] then
        cut = cut + 1
        problems[#problems + 1] = string.format("The %s at %d,%d has no door through to the rest", e.name, e.x, e.z)
      end
    end
    if ways == 0 then problems[#problems + 1] = "There is no way in: every door leads inside" end
  end
  return { problems = problems, ways = ways, cut = cut }
end

--- The base as one blueprint. Returns bp, or nil and why. Blocks the base
--- overrides by role apply to the built-in parts' letters; a part of your own
--- keeps its own blocks, merged in by what they are.
function M.compile(base, read)
  if #base.parts == 0 then return nil, "this base has no parts" end
  local _, bps = occupancy(base, read)
  if not _ then return nil, bps end
  local height = 0
  for _, bp in ipairs(bps) do height = math.max(height, bp.sy) end
  local out = B.new(base.w * P.TILE, height, base.d * P.TILE, base.name)
  local byIdentity = {}
  local function keyFor(block)
    local id = block.id .. "#" .. block.meta
    if byIdentity[id] then return byIdentity[id] end
    local k = B.freeKey(out)
    if not k then return nil end
    B.addBlock(out, k, block.id, block.meta, block.label)
    byIdentity[id] = k
    return k
  end
  for i, e in ipairs(base.parts) do
    local bp = bps[i]
    local builtin = P.LIBRARY[e.name] ~= nil
    local map = {}
    local ox, oz = (e.x - 1) * P.TILE, (e.z - 1) * P.TILE
    for _, c in ipairs(B.each(bp)) do
      local ch = c[4]
      if not map[ch] then
        map[ch] = keyFor((builtin and base.blocks[ch]) or bp.palette[ch])
        if not map[ch] then return nil, "too many different blocks for one blueprint" end
      end
      B.set(out, ox + c[1], c[2], oz + c[3], map[ch])
    end
  end
  return out
end

-- ── The file ───────────────────────────────────────────────────────────
function M.serialize(base)
  local lines = { MAGIC, "name " .. base.name, string.format("size %d %d", base.w, base.d) }
  for _, r in ipairs(P.ROLES) do
    local b = base.blocks[r.key]
    if b then lines[#lines + 1] = string.format("block %s %s %d %s", r.key, b.id, b.meta, b.label) end
  end
  for _, e in ipairs(base.parts) do
    lines[#lines + 1] = string.format("part %s %d %d %d", e.name, e.x, e.z, e.turns or 0)
  end
  return table.concat(lines, "\n") .. "\n"
end

--- Parse a base. Returns it, or nil and what is wrong and where.
function M.parse(text)
  if not M.is(text) then return nil, "not a base" end
  local base
  local name = "Untitled base"
  local n = 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    local function bad(why) return nil, string.format("line %d: %s", n, why) end
    local w, d = line:match("^size (%d+) (%d+)$")
    local ch, id, meta, label = line:match("^block (%S+) (%S+) (%d+) ?(.*)$")
    local pname, px, pz, turns = line:match("^part (%S+) (%d+) (%d+) (%d)$")
    if n == 1 or line == "" then -- the magic, or nothing
    elseif line:match("^name ") then
      name = B.cleanName(line:sub(6))
      if base then base.name = name end
    elseif w then
      w, d = tonumber(w), tonumber(d)
      if w < 1 or d < 1 or w > M.MAX_TILES or d > M.MAX_TILES then
        return bad("a base is 1 to " .. M.MAX_TILES .. " tiles each way")
      end
      base = M.new(w, d, name)
    elseif not base then
      return bad("the size comes first")
    elseif ch then
      local scratch = B.new(1, 1, 1)
      local ok, err = B.addBlock(scratch, ch, id, meta, label)
      if not ok then return bad(err) end
      base.blocks[ch] = scratch.palette[ch]
    elseif pname then
      base.parts[#base.parts + 1] = { name = pname, x = tonumber(px), z = tonumber(pz), turns = tonumber(turns) % 4 }
    else
      return bad("what is this?")
    end
  end
  if not base then return nil, "this base has no size" end
  return base
end

return M
