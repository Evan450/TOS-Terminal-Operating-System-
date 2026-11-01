-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: the blueprint                                       ║
-- ║                                                              ║
-- ║  A building as a box of cells, each holding one key from a   ║
-- ║  palette of blocks, and a text file that says the same.      ║
-- ║  A blueprint comes from other people, so it is parsed by     ║
-- ║  hand and never executed. Pure: no fs, no GPU.               ║
-- ║                                                              ║
-- ║  Coordinates are 1-based. X runs east, Y up, Z south.        ║
-- ╚══════════════════════════════════════════════════════════════╝

local B = {}

B.MAX_SIDE = 64
B.AIR = "."
local MAGIC = "PREFAB1"

--- A cell's key in the sparse table. Only built cells take memory, so an
--- empty 64x64x64 box costs nothing.
local function key(bp, x, y, z)
  return (z - 1) * bp.sy * bp.sx + (y - 1) * bp.sx + x
end

function B.new(sx, sy, sz, name)
  return { name = name or "Untitled", sx = sx, sy = sy, sz = sz,
           palette = {}, order = {}, cells = {} }
end

--- Add a block to the palette. Returns its key, or nil and why.
function B.addBlock(bp, ch, id, meta, label)
  if type(ch) ~= "string" or not ch:match("^%w$") then return nil, "a key is one letter or digit" end
  if type(id) ~= "string" or not id:match("^[%w_%-%.]+:[%w_%-%./]+$") then
    return nil, "a block is modname:blockname"
  end
  meta = tonumber(meta) or 0
  if meta < 0 or meta > 65535 or meta ~= math.floor(meta) then return nil, "damage is 0 to 65535" end
  if not bp.palette[ch] then bp.order[#bp.order + 1] = ch end
  bp.palette[ch] = { id = id, meta = meta, label = label ~= "" and label or id }
  return ch
end

--- The first key not yet used, or nil with all 62 taken.
function B.freeKey(bp)
  local keys = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  for i = 1, #keys do
    local c = keys:sub(i, i)
    if not bp.palette[c] then return c end
  end
end

function B.inside(bp, x, y, z)
  return x >= 1 and x <= bp.sx and y >= 1 and y <= bp.sy and z >= 1 and z <= bp.sz
end

--- The key at a cell, or nil for air and for anywhere outside.
function B.get(bp, x, y, z)
  if not B.inside(bp, x, y, z) then return nil end
  return bp.cells[key(bp, x, y, z)]
end

function B.set(bp, x, y, z, ch)
  if B.inside(bp, x, y, z) then bp.cells[key(bp, x, y, z)] = ch end
end

-- ── Slices ─────────────────────────────────────────────────────────────
-- The designer shows a box one slice at a time, looking along an axis.
-- Each view is a flat grid of (u, v) cells at a depth d: u runs across the
-- screen and v down it, so side views count Y from the top, the way a
-- drawing of a building reads.

--- Across, down and deep, for a view along `axis`.
function B.viewSize(bp, axis)
  if axis == "y" then return bp.sx, bp.sz, bp.sy end
  if axis == "x" then return bp.sz, bp.sy, bp.sx end
  return bp.sx, bp.sy, bp.sz
end

--- The cell at (u, v) in slice d of a view along `axis`.
function B.cellOf(bp, axis, u, v, d)
  if axis == "y" then return u, d, v end
  if axis == "x" then return d, bp.sy - v + 1, u end
  return u, bp.sy - v + 1, d
end

-- ── Editing ────────────────────────────────────────────────────────────
--- Set a list of { x, y, z } to `ch` (nil for air). Returns what it takes
--- to undo that, or nil if nothing changed.
function B.paint(bp, list, ch)
  local undo = {}
  for _, c in ipairs(list) do
    if B.inside(bp, c[1], c[2], c[3]) then
      local k = key(bp, c[1], c[2], c[3])
      if bp.cells[k] ~= ch then
        undo[#undo + 1] = { k, bp.cells[k] }
        bp.cells[k] = ch
      end
    end
  end
  if #undo > 0 then return undo end
end

--- Put back what paint returned.
function B.undo(bp, undo)
  for i = #undo, 1, -1 do
    local e = undo[i]
    bp.cells[e[1]] = e[2]
  end
end

--- A rectangle of cells in one slice, either corner first.
function B.rect(bp, axis, d, u1, v1, u2, v2)
  local out = {}
  for v = math.min(v1, v2), math.max(v1, v2) do
    for u = math.min(u1, u2), math.max(u1, u2) do
      local x, y, z = B.cellOf(bp, axis, u, v, d)
      out[#out + 1] = { x, y, z }
    end
  end
  return out
end

--- A slice as a table of { u, v, ch }, for pasting elsewhere.
function B.copySlice(bp, axis, d)
  local uw, vh = B.viewSize(bp, axis)
  local out = { axis = axis }
  for v = 1, vh do
    for u = 1, uw do
      local x, y, z = B.cellOf(bp, axis, u, v, d)
      out[#out + 1] = { u, v, B.get(bp, x, y, z) or false }
    end
  end
  return out
end

--- Paste a copied slice at depth d. Returns the undo. A clip from another
--- axis is refused, because its shape need not fit.
function B.pasteSlice(bp, clip, axis, d)
  if clip.axis ~= axis then return nil, "that slice was copied looking along " .. clip.axis:upper() end
  local undo = {}
  for _, c in ipairs(clip) do
    local x, y, z = B.cellOf(bp, axis, c[1], c[2], d)
    local one = B.paint(bp, { { x, y, z } }, c[3] or nil)
    if one then undo[#undo + 1] = one[1] end
  end
  if #undo > 0 then return undo end
  return nil
end

-- ── Counting ───────────────────────────────────────────────────────────
--- Every built cell in build order's raw form: bottom layer first.
function B.each(bp)
  local out = {}
  for y = 1, bp.sy do
    for z = 1, bp.sz do
      for x = 1, bp.sx do
        local ch = B.get(bp, x, y, z)
        if ch then out[#out + 1] = { x, y, z, ch } end
      end
    end
  end
  return out
end

--- { { key, id, meta, label, count }, ... } most used first, and the total.
function B.materials(bp)
  local counts, total = {}, 0
  for _, ch in pairs(bp.cells) do
    counts[ch] = (counts[ch] or 0) + 1
    total = total + 1
  end
  local out = {}
  for ch, n in pairs(counts) do
    local p = bp.palette[ch] or {}
    out[#out + 1] = { key = ch, id = p.id or "?", meta = p.meta or 0,
                      label = p.label or ("unknown block " .. ch), count = n }
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
  end)
  return out, total
end

-- ── The file ───────────────────────────────────────────────────────────
function B.serialize(bp)
  local lines = { MAGIC, "name " .. bp.name,
                  string.format("size %d %d %d", bp.sx, bp.sy, bp.sz) }
  for _, ch in ipairs(bp.order) do
    local p = bp.palette[ch]
    lines[#lines + 1] = string.format("block %s %s %d %s", ch, p.id, p.meta, p.label)
  end
  for y = 1, bp.sy do
    lines[#lines + 1] = "layer " .. y
    for z = 1, bp.sz do
      local row = {}
      for x = 1, bp.sx do row[x] = B.get(bp, x, y, z) or B.AIR end
      lines[#lines + 1] = table.concat(row)
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

--- A name a blueprint can safely have: one line, at most 32 characters.
function B.cleanName(s)
  s = tostring(s or ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return s:sub(1, 32)
end

--- Parse a blueprint. Returns it, or nil and what is wrong and where.
function B.parse(text)
  if type(text) ~= "string" then return nil, "not a blueprint" end
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
  if lines[1] ~= MAGIC then return nil, "not a blueprint" end
  local bp, y, z = nil, nil, nil
  local name = "Untitled"
  for n = 2, #lines do
    local line = lines[n]
    local function bad(why) return nil, string.format("line %d: %s", n, why) end
    local sx, sy, sz = line:match("^size (%d+) (%d+) (%d+)$")
    local ch, id, meta, label = line:match("^block (%S+) (%S+) (%d+) ?(.*)$")
    local lay = line:match("^layer (%d+)$")
    if line == "" then -- a blank line means nothing
    elseif line:match("^name ") then
      name = B.cleanName(line:sub(6))
      if bp then bp.name = name end
    elseif sx then
      sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
      if sx < 1 or sy < 1 or sz < 1 or sx > B.MAX_SIDE or sy > B.MAX_SIDE or sz > B.MAX_SIDE then
        return bad("each side is 1 to " .. B.MAX_SIDE)
      end
      bp = B.new(sx, sy, sz, name)
    elseif not bp then
      return bad("the size comes first")
    elseif ch then
      local ok, err = B.addBlock(bp, ch, id, meta, label)
      if not ok then return bad(err) end
    elseif lay then
      y, z = tonumber(lay), 0
      if y < 1 or y > bp.sy then return bad("no such layer") end
    elseif y then
      z = z + 1
      if z > bp.sz then return bad("too many rows in layer " .. y) end
      if #line ~= bp.sx then return bad("a row is " .. bp.sx .. " wide") end
      for x = 1, bp.sx do
        local c = line:sub(x, x)
        if c ~= B.AIR then
          if not bp.palette[c] then return bad("no block '" .. c .. "'") end
          B.set(bp, x, y, z, c)
        end
      end
    else
      return bad("what is this?")
    end
  end
  if not bp then return nil, "this blueprint has no size" end
  return bp
end

return B
