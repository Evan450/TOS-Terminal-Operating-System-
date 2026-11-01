-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: working with the rest of the pack                   ║
-- ║                                                              ║
-- ║  None of these is needed to design or build anything. Each   ║
-- ║  does something more when another package is there: stock    ║
-- ║  watches a build's materials, printer prints its plans, and  ║
-- ║  calc opens its bill of materials.                           ║
-- ║                                                              ║
-- ║  Pure: the other package's library is handed in, so this     ║
-- ║  file names nothing it cannot do without.                    ║
-- ╚══════════════════════════════════════════════════════════════╝

local B = require("prefab.blueprint")
local P = require("prefab.plan")

local L = {}

--- An item's identity, the same way stock and the inventory library spell
--- it: registry name and damage, never the label.
function L.key(id, meta) return id .. "#" .. tostring(meta) end

--- Every stack on every side of a transposer or inventory controller.
--- Returns the stacks and the sides read, or nil and why.
function L.scan(inv)
  if not inv.available() then return nil, "no inventory controller or transposer attached" end
  local sides = inv.sides()
  if #sides == 0 then return nil, "no inventories found on any side" end
  local stacks, names = {}, {}
  for _, s in ipairs(sides) do
    local list = inv.stacks(s.side)
    if list then
      names[#names + 1] = s.name
      for _, st in ipairs(list) do stacks[#stacks + 1] = st end
    end
  end
  return stacks, names
end

--- A build's materials against what was read. Returns rows of { label, id,
--- key, need, have, short }, most short first, and the total short.
function L.need(bp, stacks)
  local have = {}
  for _, st in ipairs(stacks or {}) do
    have[st.key] = (have[st.key] or 0) + (tonumber(st.count) or 0)
  end
  local rows, short = {}, 0
  for _, m in ipairs((B.materials(bp))) do
    local key = L.key(m.id, m.meta)
    local got = have[key] or 0
    local miss = math.max(0, m.count - got)
    rows[#rows + 1] = { label = m.label, id = m.id, key = key, need = m.count, have = got, short = miss }
    short = short + miss
  end
  table.sort(rows, function(a, b)
    if a.short ~= b.short then return a.short > b.short end
    return a.key < b.key
  end)
  return rows, short
end

--- Add a build to stock's watch list, read and saved with stock's own
--- functions. A threshold someone already set stays if it is the higher one.
--- Returns how many blocks it covers.
function L.watch(watches, labels, bp)
  local n = 0
  for _, m in ipairs((B.materials(bp))) do
    local key = L.key(m.id, m.meta)
    watches[key] = math.max(watches[key] or 0, m.count)
    labels[key] = labels[key] or (tostring(m.label):gsub("[\t\r\n]", " "))
    n = n + 1
  end
  return n
end

--- Take a build back off the list. Only thresholds that are exactly what
--- this build set go: anything else is somebody's own.
function L.unwatch(watches, labels, bp)
  local n = 0
  for _, m in ipairs((B.materials(bp))) do
    local key = L.key(m.id, m.meta)
    if watches[key] == m.count then
      watches[key], labels[key] = nil, nil
      n = n + 1
    end
  end
  return n
end

--- The bill of materials as CSV. With rows from L.need it says what is in
--- hand too.
function L.csv(bp, rows)
  local function field(v)
    v = tostring(v)
    if v:find('[,"\r\n]') then return '"' .. v:gsub('"', '""') .. '"' end
    return v
  end
  local lines = {}
  local head = { "Block", "Registry name", "Damage", "Count", "Stacks" }
  if rows then head[6], head[7] = "Have", "Short" end
  lines[1] = table.concat(head, ",")
  local byKey = {}
  for _, r in ipairs(rows or {}) do byKey[r.key] = r end
  for _, m in ipairs((B.materials(bp))) do
    local out = { field(m.label), field(m.id), m.meta, m.count, math.ceil(m.count / P.STACK) }
    local r = byKey[L.key(m.id, m.meta)]
    if r then out[6], out[7] = r.have, r.short end
    lines[#lines + 1] = table.concat(out, ",")
  end
  return table.concat(lines, "\n") .. "\n"
end

--- Letters that print the same width. A printer's font is proportional, so
--- a blueprint's own keys would not line up: `i` and `l` are narrow.
local GLYPHS = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
local CELL_WIDTH = 6                   -- pixels, those letters and the dash

--- The plans as a printer job: a sheet of materials, then one grid a layer,
--- in strips where a row is wider than the paper.
function L.printJob(job, bp, report, maxWidth)
  job:line(bp.name, nil, "center")
  job:line(string.format("%d x %d x %d, %d blocks", bp.sx, bp.sy, bp.sz, report.total), nil, "center")
  job:blank()
  local letter = {}
  for i, ch in ipairs(bp.order) do letter[ch] = GLYPHS:sub((i - 1) % #GLYPHS + 1, (i - 1) % #GLYPHS + 1) end
  for _, m in ipairs(report.materials) do
    job:line(string.format("%s  %d  %s", letter[m.key] or "?", m.count, m.label))
  end
  job:blank()
  job:line("- is air. North is at the top of each plan.")

  local perRow = math.max(1, math.floor(maxWidth / CELL_WIDTH))
  for y = 1, bp.sy do
    for from = 1, bp.sx, perRow do
      local to = math.min(bp.sx, from + perRow - 1)
      job:pageBreak()
      job:line(bp.sx > perRow and string.format("Layer %d, X %d to %d", y, from, to)
        or string.format("Layer %d of %d", y, bp.sy))
      for z = 1, bp.sz do
        local row = {}
        for x = from, to do
          local ch = B.get(bp, x, y, z)
          row[#row + 1] = ch and letter[ch] or "-"
        end
        job:line(table.concat(row))
      end
    end
  end
  return job
end

return L
