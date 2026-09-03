-- ╔══════════════════════════════════════╗
-- ║  TOS Peripheral - Inventory Control  ║
-- ╚══════════════════════════════════════╝

local hal   = require("kernel.hal")
local sides = require("compat.sides")

local inv = {}
local icProxy       -- inventory_controller proxy
local transProxy    -- transposer proxy
local mode          -- "ic" | "transposer" | nil

-- #SEC L (hot-plug cache invalidation) — reset cached proxies when the
-- underlying component is removed. Without this, a transposer ripped
-- out at runtime leaves transProxy stale; next call crashes on
-- proxy.<method> against a no-longer-valid address. Subscribed
-- lazily so the kernel.event require can fail gracefully on early
-- boot.
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
        -- New component appeared: drop the cache so detect() re-resolves.
        resetCache()
      end
    end, "peripheral.inventory")
  end
end

-- ============================================================
-- Internal helpers
-- ============================================================

local function detect()
  -- #SEC H34 — peripheral.inventory cap required.
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

-- #SEC M-14 — coerce/range-check count and slot args before they reach an
-- in-world machine. Without this a caller could pass a negative count, a
-- NaN, a string, or a fractional/zero slot and have it forwarded straight
-- to the transposer / inventory_controller proxy.
local function vCount(n)
  n = tonumber(n)
  if not n or n ~= n then return 64 end       -- nil/NaN → default stack
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

--- Full stack detail for every occupied slot on `side`.
--
-- Why this exists next to inv.list(): list() collapses `label` and `name`
-- into one field, which is fine for "show me this chest" and wrong for
-- anything that AGGREGATES. Two mods can ship different items whose
-- display label is "Copper Ingot", and one mod's item can be relabelled
-- by an anvil — so a count keyed on the label silently merges things that
-- are not the same item, and splits things that are. Callers that total
-- across containers need the registry `name` (plus damage, which is what
-- distinguishes wool colours and tool wear) as the identity, and the
-- label only for display.
--
-- Returns an array of { slot, id, label, count, max, damage }, or nil, err.
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
      -- Identity for aggregation: registry name + damage. Deliberately
      -- NOT the label (see above).
      key    = id .. "#" .. tostring(dmg),
    }
  end

  -- Fast path. getAllStacks returns the WHOLE inventory in one component
  -- call; the per-slot loop is one call per slot, and a double chest is
  -- 54 of them per side. On a Minecraft computer that difference is the
  -- difference between a scan you can run live and one you cannot.
  if p.getAllStacks then
    local okA, arr = pcall(p.getAllStacks, s)
    if okA and arr then
      local okG, all = pcall(function() return arr.getAll() end)
      if okG and type(all) == "table" then
        local items = {}
        -- getAll() is 0-based, unlike everything else in this file.
        for i = 0, #all do
          local st = normalize(i + 1, all[i])
          if st then items[#items + 1] = st end
        end
        return items
      end
    end
  end

  -- Fallback: per-slot. Correct everywhere, slow on big containers.
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

--- Which sides currently have an inventory attached.
--- Returns an array of { side = N, name = "north", size = N }.
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
  count = vCount(count)  -- #SEC M-14
  -- #SEC M-14 — slots are optional; when present they must be valid.
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
  local vs, se = vSlot(slot); if not vs then return nil, se end  -- #SEC M-14
  local ok, result = pcall(icProxy.suckFromSlot, s, vs, vCount(count))
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
  local vs, se = vSlot(slot); if not vs then return nil, se end  -- #SEC M-14
  local ok, result = pcall(icProxy.dropIntoSlot, s, vs, vCount(count))
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
