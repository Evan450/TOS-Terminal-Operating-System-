








local S = {}












--! Identity is `key` (registry name + damage), NOT the label. Two mods
--! can both ship a "Copper Ingot", and an anvil can rename any item —
--! keying on the display name silently merges different items and splits
--! identical ones, which is the one thing a stock count must never do.
--! The label is carried for DISPLAY only, and the first one seen wins so
--! the reading stays stable between refreshes.
function S.aggregate(readings)
  local byKey, order = {}, {}
  for _, r in ipairs(readings or {}) do
    if type(r) == "table" and r.key and (tonumber(r.count) or 0) > 0 then
      local row = byKey[r.key]
      if not row then
        row = {
          key = r.key, id = r.id, label = r.label or r.id or "?",
          total = 0, stacks = 0, sides = {}, _sideSeen = {},
        }
        byKey[r.key] = row
        order[#order + 1] = row
      end
      row.total  = row.total + (tonumber(r.count) or 0)
      row.stacks = row.stacks + 1
      local sn = r.sideName
      if sn and not row._sideSeen[sn] then
        row._sideSeen[sn] = true
        row.sides[#row.sides + 1] = sn
      end
    end
  end
  for _, row in ipairs(order) do
    row._sideSeen = nil
    table.sort(row.sides)
  end
  table.sort(order, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return (a.label or "") < (b.label or "")
  end)
  return order
end











function S.applyWatches(rows, watches, labels)
  rows = rows or {}
  watches = watches or {}
  labels = labels or {}
  local seen = {}
  for _, row in ipairs(rows) do
    seen[row.key] = true
    local min = tonumber(watches[row.key])
    if min then
      row.min = min
      row.low = row.total < min
    end
  end
  local missing = {}
  for key, min in pairs(watches) do
    if not seen[key] and tonumber(min) then
      missing[#missing + 1] = {
        key = key, id = key:match("^(.-)#") or key,
        label = labels[key] or key:match("^(.-)#") or key,
        total = 0, stacks = 0, sides = {},
        min = tonumber(min), low = true, absent = true,
      }
    end
  end
  table.sort(missing, function(a, b) return (a.label or "") < (b.label or "") end)
  local out = {}
  for _, r in ipairs(missing) do out[#out + 1] = r end
  for _, r in ipairs(rows) do out[#out + 1] = r end
  return out
end



function S.lowStock(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    if row.low then out[#out + 1] = row end
  end
  table.sort(out, function(a, b)
    local da = (a.min or 0) - (a.total or 0)
    local db = (b.min or 0) - (b.total or 0)
    if da ~= db then return da > db end
    return (a.label or "") < (b.label or "")
  end)
  return out
end







function S.filter(rows, query)
  if not query or query == "" then return rows or {} end
  local q = tostring(query):lower()
  local out = {}
  for _, row in ipairs(rows or {}) do
    local label = tostring(row.label or ""):lower()
    local id    = tostring(row.id or ""):lower()
    if label:find(q, 1, true) or id:find(q, 1, true) then
      out[#out + 1] = row
    end
  end
  return out
end



function S.fmtCount(n)
  n = tonumber(n) or 0
  if n < 10000 then return tostring(math.floor(n)) end
  if n < 1000000 then return string.format("%.1fk", n / 1000) end
  return string.format("%.1fM", n / 1000000)
end



function S.fmtStacks(count, maxStack)
  count = tonumber(count) or 0
  maxStack = tonumber(maxStack) or 64
  if maxStack < 1 then maxStack = 64 end
  if count < maxStack then return tostring(math.floor(count)) end
  local s = math.floor(count / maxStack)
  local r = math.floor(count % maxStack)
  if r == 0 then return s .. "s" end
  return s .. "s+" .. r
end


function S.totals(rows)
  local items, distinct, slots = 0, 0, 0
  for _, row in ipairs(rows or {}) do
    if not row.absent then
      items = items + (row.total or 0)
      slots = slots + (row.stacks or 0)
      distinct = distinct + 1
    end
  end
  return { items = items, distinct = distinct, slots = slots }
end









function S.encodeWatches(watches, labels)
  local keys = {}
  for k in pairs(watches or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = {}
  for _, k in ipairs(keys) do
    local min = tonumber(watches[k])
    if min and not tostring(k):find("[\t\n\r]") then
      lines[#lines + 1] = string.format("%s\t%d\t%s",
        k, math.floor(min), tostring((labels or {})[k] or ""))
    end
  end
  return table.concat(lines, "\n")
end

function S.decodeWatches(text)
  local watches, labels = {}, {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local key, min, label = line:match("^([^\t]+)\t(%-?%d+)\t?(.*)$")
    if key and min then
      local n = tonumber(min)
      if n and n >= 0 then
        watches[key] = n
        if label and label ~= "" then labels[key] = label end
      end
    end
  end
  return watches, labels
end

return S
