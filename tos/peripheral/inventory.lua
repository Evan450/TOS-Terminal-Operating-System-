local hal   = require("kernel.hal")
local sides = require("compat.sides")

local inv = {}
local icProxy
local transProxy
local mode

local function resetCache()
  icProxy = nil
  transProxy = nil
  mode = nil
end
do
  local okE, eventMod = pcall(require, "kernel.event")
  if okE and eventMod and eventMod.on then
    eventMod.on("component_removed", function(_, addr, ctype)
      if ctype == "inventory_controller" or ctype == "transposer" or ctype == "tank_controller" then
        resetCache()
      end
    end, "peripheral.inventory")
    eventMod.on("component_added", function(_, addr, ctype)
      if ctype == "inventory_controller" or ctype == "transposer" then

        resetCache()
      end
    end, "peripheral.inventory")
  end
end

local function detect()

  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.current then
    local cur = procMod.current()
    if cur and not (cur.caps and cur.caps["peripheral.inventory"]) then
      return nil
    end
  end
  if mode then return mode end
  icProxy = hal.proxy("inventory_controller")
  if icProxy then
    mode = "ic"
    return mode
  end
  transProxy = hal.proxy("transposer")
  if transProxy then
    mode = "transposer"
    return mode
  end
  return nil
end

local function resolveSide(side)
  if type(side) == "string" then
    local n = sides[side:lower()]
    if not n then return nil, "unknown side: " .. side end
    return n
  elseif type(side) == "number" and side >= 0 and side <= 5 then
    return side
  end
  return nil, "invalid side"
end

local function vCount(n)
  n = tonumber(n)
  if not n or n ~= n then return 64 end
  n = math.floor(n)
  if n < 0 then n = 0 end
  return n
end
local function vSlot(n)
  n = tonumber(n)
  if not n or n ~= n then return nil, "invalid slot" end
  n = math.floor(n)
  if n < 1 then return nil, "invalid slot (must be >= 1)" end
  return n
end

function inv.size(side)
  if not detect() then return nil, "no inventory component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local p = icProxy or transProxy
  local ok, result = pcall(p.getInventorySize, s)
  if not ok then return nil, "no inventory on that side" end
  return result
end

function inv.getSlot(side, slot)
  if not detect() then return nil, "no inventory component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local p = icProxy or transProxy
  local ok, result = pcall(p.getStackInSlot, s, slot)
  if not ok then return nil, "failed to read slot" end
  return result
end

function inv.getInternalSlot(slot)
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  local ok, result = pcall(icProxy.getStackInInternalSlot, slot)
  if not ok then return nil, "failed to read internal slot" end
  return result
end

function inv.list(side)
  if not detect() then return nil, "no inventory component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local p = icProxy or transProxy
  local ok, sz = pcall(p.getInventorySize, s)
  if not ok or not sz then return nil, "no inventory on that side" end
  local items = {}
  for i = 1, sz do
    local sok, stack = pcall(p.getStackInSlot, s, i)
    if sok and stack then
      items[#items + 1] = {
        slot  = i,
        name  = stack.label or stack.name or "?",
        count = stack.size or stack.count or 0,
      }
    end
  end
  return items
end

function inv.stacks(side)
  if not detect() then return nil, "no inventory component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local p = icProxy or transProxy

  local function normalize(slot, stack)
    if type(stack) ~= "table" then return nil end
    local count = tonumber(stack.size or stack.count) or 0
    if count <= 0 then return nil end
    local id = stack.name or stack.label or "?"
    local dmg = tonumber(stack.damage) or 0
    return {
      slot   = slot,
      id     = id,
      label  = stack.label or stack.name or "?",
      count  = count,
      max    = tonumber(stack.maxSize or stack.maxDamage) or nil,
      damage = dmg,

      key    = id .. "#" .. tostring(dmg),
    }
  end

  if p.getAllStacks then
    local okA, arr = pcall(p.getAllStacks, s)
    if okA and arr then
      local okG, all = pcall(function() return arr.getAll() end)
      if okG and type(all) == "table" then
        local items = {}

        for i = 0, #all do
          local st = normalize(i + 1, all[i])
          if st then items[#items + 1] = st end
        end
        return items
      end
    end
  end

  local okSz, sz = pcall(p.getInventorySize, s)
  if not okSz or not sz then return nil, "no inventory on that side" end
  local items = {}
  for i = 1, sz do
    local sok, stack = pcall(p.getStackInSlot, s, i)
    if sok then
      local st = normalize(i, stack)
      if st then items[#items + 1] = st end
    end
  end
  return items
end

function inv.sides()
  if not detect() then return {} end
  local p = icProxy or transProxy
  local out = {}
  local NAMES = { [0] = "bottom", "top", "north", "south", "west", "east" }
  for s = 0, 5 do
    local ok, sz = pcall(p.getInventorySize, s)
    if ok and type(sz) == "number" and sz > 0 then
      out[#out + 1] = { side = s, name = NAMES[s] or tostring(s), size = sz }
    end
  end
  return out
end

function inv.transfer(fromSide, toSide, count, fromSlot, toSlot)
  if not detect() then return nil, "no inventory component" end
  count = vCount(count)

  if fromSlot ~= nil then
    local v, e = vSlot(fromSlot); if not v then return nil, "fromSlot: " .. e end
    fromSlot = v
  end
  if toSlot ~= nil then
    local v, e = vSlot(toSlot); if not v then return nil, "toSlot: " .. e end
    toSlot = v
  end

  if mode == "transposer" then
    local fs, ferr = resolveSide(fromSide)
    if not fs then return nil, ferr end
    local ts, terr = resolveSide(toSide)
    if not ts then return nil, terr end
    local ok, result = pcall(transProxy.transferItem, fs, ts, count, fromSlot, toSlot)
    if not ok then return nil, "transfer failed" end
    return result
  end

  if mode == "ic" then
    local ts, terr = resolveSide(toSide)
    if not ts then return nil, terr end
    if toSlot then
      local ok, result = pcall(icProxy.dropIntoSlot, ts, toSlot, count)
      if not ok then return nil, "drop failed" end
      return result
    else

      local ok, result = pcall(icProxy.dropIntoSlot, ts, 1, count)
      if not ok then return nil, "drop failed" end
      return result
    end
  end

  return nil, "no transfer method available"
end

function inv.suckFromSlot(side, slot, count)
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local vs, se = vSlot(slot); if not vs then return nil, se end
  local ok, result = pcall(icProxy.suckFromSlot, s, vs, vCount(count))
  if not ok then return nil, "suck failed" end
  return result
end

function inv.dropIntoSlot(side, slot, count)
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local vs, se = vSlot(slot); if not vs then return nil, se end
  local ok, result = pcall(icProxy.dropIntoSlot, s, vs, vCount(count))
  if not ok then return nil, "drop failed" end
  return result
end

function inv.equip()
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  return icProxy.equip()
end

function inv.available()
  return detect() ~= nil
end

function inv.getMode()
  detect()
  return mode
end

function inv.refresh()
  icProxy, transProxy, mode = nil, nil, nil
  return detect() ~= nil
end

return inv
