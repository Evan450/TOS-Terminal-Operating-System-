-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: reading a site with a geolyzer                      ║
-- ║                                                              ║
-- ║  geolyzer.scan is noisy, but only about what a block IS.     ║
-- ║  EventHandlerVanilla writes exactly 0 for air, for anything  ║
-- ║  replaceable and for an unloaded chunk, and hardness plus    ║
-- ║  up to distance * 2 / 33 for the rest. So "is something      ║
-- ║  there?" has no noise in it at all, and that is the only     ║
-- ║  question a building site asks. Each cell needs one reading. ║
-- ║                                                              ║
-- ║  Pure: it is handed a scan function, so the whole of this    ║
-- ║  runs against a simulated world off-box.                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local S = {}

S.RANGE = 32           -- how far a scan reaches on each axis, by default
S.CUBE  = 4            -- 4x4x4 is the 64 cells one call can hold
S.COST  = 10           -- energy a call: charged once, whatever its size
S.RATE  = 20           -- calls a second: one a tick
S.NOISE = 2 / 33       -- at most this much noise per block of distance
S.RETRIES = 8          -- waits for the machine's power before giving up

local AIR, SOLID, LIQUID, FIXED = 0, 1, 2, 3
S.AIR, S.SOLID, S.LIQUID, S.FIXED = AIR, SOLID, LIQUID, FIXED

--- What a reading means. Water and lava have a hardness of 100 and the
--- hardest ordinary block has 50, so a liquid stands clear of the noise;
--- bedrock is -1, which can only be told apart close to the geolyzer.
function S.classify(v, dist)
  if v == 0 then return AIR end
  local n = dist * S.NOISE
  if v - n >= 60 then return LIQUID end
  if v + n < 0 then return FIXED end
  return SOLID
end

--- How many calls a box of this size takes.
function S.calls(w, d, h)
  local c = S.CUBE
  return math.ceil(w / c) * math.ceil(d / c) * math.ceil(h / c)
end

--- Why this box cannot be scanned, or nil. x, z and y are offsets from
--- the geolyzer, at the box's low corner.
function S.check(box)
  for _, n in ipairs({ "w", "d", "h" }) do
    if box[n] < 1 then return "a site is at least 1 block each way" end
  end
  local r = S.RANGE
  if math.abs(box.x) > r or math.abs(box.x + box.w - 1) > r
     or math.abs(box.z) > r or math.abs(box.z + box.d - 1) > r then
    return "that site reaches past the geolyzer's range of " .. r .. " blocks"
  end
  if math.abs(box.y) > r or math.abs(box.y + box.h - 1) > r then
    return "that height reaches past the geolyzer's range of " .. r .. " blocks"
  end
end

--- One call, waiting out a machine that has run short of power.
--- scan returns a table, or nil and why, or throws on bad arguments.
local function call(scan, wait, x, z, y, w, d, h)
  for _ = 1, S.RETRIES do
    local ok, data, err = pcall(scan, x, z, y, w, d, h)
    if not ok then return nil, tostring(data) end
    if type(data) == "table" then return data end
    if err ~= "not enough energy" then return nil, tostring(err) end
    if wait then wait() end
  end
  return nil, "not enough energy, and it did not recover"
end

--- Scan a box. Returns a site, or nil and why. A column is a list of runs
--- of one class, as y1, y2, class: only what is there takes memory.
--- Cubes go bottom layer first and a cube's cells come up in y, so each
--- column's runs arrive in order.
function S.survey(scan, box, opts)
  opts = opts or {}
  local bad = S.check(box)
  if bad then return nil, bad end
  local w, d, h = box.w, box.d, box.h
  local site = { x = box.x, z = box.z, y = box.y, w = w, d = d, h = h, cols = {}, calls = 0 }
  local cols = site.cols
  for i = 1, w * d do cols[i] = {} end
  local total = S.calls(w, d, h)
  local c = S.CUBE

  for by = 0, h - 1, c do
    local ch = math.min(c, h - by)
    for bz = 0, d - 1, c do
      local cd = math.min(c, d - bz)
      for bx = 0, w - 1, c do
        local cw = math.min(c, w - bx)
        local ax, ay, az = box.x + bx, box.y + by, box.z + bz
        local data, err = call(scan, opts.wait, ax, az, ay, cw, cd, ch)
        if not data then return nil, err end
        site.calls = site.calls + 1
        for ry = 0, ch - 1 do
          for rz = 0, cd - 1 do
            for rx = 0, cw - 1 do
              -- OC's own index. The table is always 64 long, and past the
              -- box it holds raw noise, so nothing may read beyond this.
              local v = data[1 + rx + (rz + ry * cd) * cw]
              if v == nil then return nil, "a scan came back short" end
              local gx, gy, gz = ax + rx, ay + ry, az + rz
              local kind = S.classify(v, math.sqrt(gx * gx + gy * gy + gz * gz))
              if kind ~= AIR then
                local col = cols[(bz + rz) * w + bx + rx + 1]
                local n = #col
                if n > 0 and col[n] == kind and col[n - 1] == gy - 1 then
                  col[n - 1] = gy
                else
                  col[n + 1], col[n + 2], col[n + 3] = gy, gy, kind
                end
              end
            end
          end
        end
        if opts.progress then opts.progress(site.calls, total) end
      end
    end
  end
  return site
end

--- The class of a cell, by its column (1-based) and offset y.
function S.at(site, cx, cz, y)
  local col = site.cols[(cz - 1) * site.w + cx]
  for i = 1, #col, 3 do
    if y >= col[i] and y <= col[i + 1] then return col[i + 2] end
  end
  return AIR
end

--- A column's highest block, and what class it is, or nil if it is empty.
function S.top(site, cx, cz)
  local col = site.cols[(cz - 1) * site.w + cx]
  local n = #col
  if n == 0 then return nil end
  return col[n - 1], col[n]
end

--- What a floor at each height would cost. A level is the y of the
--- building's first layer. Level by level and column by column there is
--- no idea of "the ground" here, which is the point: a tree is just blocks
--- in the way, and a cave is just a gap under the floor.
--- Returns the levels, best first. Each has: y, clear (blocks in the way),
--- over (blocks above the building), fill (blocks to put under the floor),
--- liquid, fixed (cells that cannot be broken), open (columns with nothing
--- under them in the scan).
---
--- `over` counts against a level because a robot works from above. Without
--- it a cave is free, with nothing to clear and a floor already there, so
--- every site with a cave under it and a tree on it was built underground.
function S.fit(site, height)
  local levels = {}
  -- A floor needs a row under it and room over it, inside what was read.
  for y = site.y + 1, site.y + site.h - height do
    levels[#levels + 1] = { y = y, clear = 0, over = 0, fill = 0, liquid = 0, fixed = 0, open = 0 }
  end
  if #levels == 0 then return levels end
  local cls, above = {}, {}
  for cz = 1, site.d do
    for cx = 1, site.w do
      for i = 0, site.h - 1 do cls[i] = AIR end
      local col = site.cols[(cz - 1) * site.w + cx]
      for i = 1, #col, 3 do
        for y = col[i], col[i + 1] do cls[y - site.y] = col[i + 2] end
      end
      above[site.h] = 0                  -- blocks at this height and higher
      for i = site.h - 1, 0, -1 do
        local k = cls[i]
        above[i] = above[i + 1] + ((k == SOLID or k == FIXED) and 1 or 0)
      end
      for _, L in ipairs(levels) do
        local base = L.y - site.y
        for i = base, base + height - 1 do
          local k = cls[i]
          if k == SOLID then L.clear = L.clear + 1
          elseif k == LIQUID then L.liquid = L.liquid + 1
          elseif k == FIXED then L.fixed = L.fixed + 1 end
        end
        L.over = L.over + above[base + height]
        local i = base - 1
        while i >= 0 and cls[i] ~= SOLID and cls[i] ~= FIXED do i = i - 1 end
        if i < 0 then
          L.open = L.open + 1
          L.fill = L.fill + base
        else
          L.fill = L.fill + (base - 1 - i)
        end
      end
    end
  end
  table.sort(levels, function(a, b)
    if a.fixed ~= b.fixed then return a.fixed < b.fixed end
    if a.open ~= b.open then return a.open < b.open end
    local ca, cb = a.clear + a.over + a.fill, b.clear + b.over + b.fill
    if ca ~= cb then return ca < cb end
    if a.liquid ~= b.liquid then return a.liquid < b.liquid end
    return a.y > b.y
  end)
  return levels
end

--- The site from above, one character a column, against a floor at `level`.
--- `.` is ready. A digit is that many blocks standing over the row under
--- the floor, a letter is that far short of it (a is one), `~` is liquid
--- on top, and `?` is a column with nothing in the scan.
function S.map(site, level)
  local rows = {}
  local under = level - 1
  for cz = 1, site.d do
    local row = {}
    for cx = 1, site.w do
      local top, kind = S.top(site, cx, cz)
      local c
      if not top then c = "?"
      elseif kind == LIQUID then c = "~"
      elseif top == under then c = "."
      elseif top > under then
        local n = top - under
        c = n > 9 and "^" or tostring(n)
      else
        local n = under - top
        c = n > 8 and "v" or string.char(96 + n)
      end
      row[cx] = c
    end
    rows[cz] = table.concat(row)
  end
  return rows
end

return S
