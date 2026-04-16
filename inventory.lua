-- ╔══════════════════════════════════════╗
-- ║  TOS Peripheral - Inventory Control ║
-- ╚══════════════════════════════════════╝

local hal   = require("kernel.hal")
local sides = require("compat.sides")

local inv = {}
local icProxy       -- inventory_controller proxy
local transProxy    -- transposer proxy
local mode          -- "ic" | "transposer" | nil

-- ============================================================
-- Internal helpers
-- ============================================================

local function detect()
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

-- ============================================================
-- Inventory queries
-- ============================================================

--- Get inventory size on a given side.
-- @param side number|string  Side to query
-- @return number|nil, string
function inv.size(side)
  if not detect() then return nil, "no inventory component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local p = icProxy or transProxy
  local ok, result = pcall(p.getInventorySize, s)
  if not ok then return nil, "no inventory on that side" end
  return result
end

--- Get stack info for a slot in an adjacent inventory.
-- @param side number|string  Side of the inventory
-- @param slot number         Slot number (1-based)
-- @return table|nil, string  Item info table or nil
function inv.getSlot(side, slot)
  if not detect() then return nil, "no inventory component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local p = icProxy or transProxy
  local ok, result = pcall(p.getStackInSlot, s, slot)
  if not ok then return nil, "failed to read slot" end
  return result
end

--- Get stack info for a slot in the robot's own inventory.
-- Only available with inventory_controller.
-- @param slot number  Internal slot number
-- @return table|nil, string
function inv.getInternalSlot(slot)
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  local ok, result = pcall(icProxy.getStackInInternalSlot, slot)
  if not ok then return nil, "failed to read internal slot" end
  return result
end

--- List all non-empty slots in an adjacent inventory.
-- @param side number|string  Side of the inventory
-- @return table|nil, string  Sequential array of { slot=N, name=str, count=N }
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

-- ============================================================
-- Item transfer
-- ============================================================

--- Transfer items between inventories or slots.
-- With inventory_controller: drop into / suck from adjacent inventory.
-- With transposer: transfer between two sides.
-- @param fromSide number|string   Source side
-- @param toSide   number|string   Destination side
-- @param count    number          Items to move (default: 64)
-- @param fromSlot number|nil      Source slot (transposer only)
-- @param toSlot   number|nil      Destination slot (transposer only)
-- @return number|boolean|nil, string  Items moved or success
function inv.transfer(fromSide, toSide, count, fromSlot, toSlot)
  if not detect() then return nil, "no inventory component" end
  count = count or 64

  if mode == "transposer" then
    local fs, ferr = resolveSide(fromSide)
    if not fs then return nil, ferr end
    local ts, terr = resolveSide(toSide)
    if not ts then return nil, terr end
    local ok, result = pcall(transProxy.transferItem, fs, ts, count, fromSlot, toSlot)
    if not ok then return nil, "transfer failed" end
    return result
  end

  -- inventory_controller: use dropIntoSlot / suckFromSlot
  if mode == "ic" then
    local ts, terr = resolveSide(toSide)
    if not ts then return nil, terr end
    if toSlot then
      local ok, result = pcall(icProxy.dropIntoSlot, ts, toSlot, count)
      if not ok then return nil, "drop failed" end
      return result
    else
      -- Without a target slot, use the basic drop
      local ok, result = pcall(icProxy.dropIntoSlot, ts, 1, count)
      if not ok then return nil, "drop failed" end
      return result
    end
  end

  return nil, "no transfer method available"
end

--- Suck items from a specific slot in an adjacent inventory.
-- Only available with inventory_controller.
-- @param side number|string  Side to suck from
-- @param slot number         Slot to suck from
-- @param count number        Items to take (default: 64)
function inv.suckFromSlot(side, slot, count)
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local ok, result = pcall(icProxy.suckFromSlot, s, slot, count or 64)
  if not ok then return nil, "suck failed" end
  return result
end

--- Drop items into a specific slot in an adjacent inventory.
-- Only available with inventory_controller.
-- @param side number|string  Side to drop into
-- @param slot number         Target slot
-- @param count number        Items to drop (default: 64)
function inv.dropIntoSlot(side, slot, count)
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local ok, result = pcall(icProxy.dropIntoSlot, s, slot, count or 64)
  if not ok then return nil, "drop failed" end
  return result
end

-- ============================================================
-- Tool management
-- ============================================================

--- Swap equipped tool with selected inventory slot.
-- Only available with inventory_controller.
function inv.equip()
  if not detect() or mode ~= "ic" then
    return nil, "requires inventory_controller"
  end
  return icProxy.equip()
end

-- ============================================================
-- Status
-- ============================================================

--- Check if an inventory component is available.
function inv.available()
  return detect() ~= nil
end

--- Get which component mode is active.
-- @return string|nil  "ic", "transposer", or nil
function inv.getMode()
  detect()
  return mode
end

--- Refresh proxies (useful after hot-plug).
function inv.refresh()
  icProxy, transProxy, mode = nil, nil, nil
  return detect() ~= nil
end

return inv
