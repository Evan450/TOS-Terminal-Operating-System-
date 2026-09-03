-- ╔══════════════════════════════════════╗
-- ║  TOS Peripheral - Robot Control      ║
-- ╚══════════════════════════════════════╝

local hal   = require("kernel.hal")
local sides = require("compat.sides")

local robot = {}
local proxy  -- lazy-loaded robot proxy

-- #SEC L — reset cached proxy on hot-plug.
do
  local okE, eventMod = pcall(require, "kernel.event")
  if okE and eventMod and eventMod.on then
    local function reset(_, addr, ctype)
      if ctype == "robot" then proxy = nil end
    end
    eventMod.on("component_removed", reset, "peripheral.robot")
    eventMod.on("component_added",   reset, "peripheral.robot")
  end
end

-- ============================================================
-- Internal helpers
-- ============================================================

local function getProxy()
  -- #SEC H34 — gate every entry point through a per-call cap check.
  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.current then
    local cur = procMod.current()
    if cur and not (cur.caps and cur.caps["peripheral.robot"]) then
      return nil
    end
  end
  if not proxy then
    proxy = hal.proxy("robot")
  end
  return proxy
end

local function resolveSide(side)
  if side == nil then return 3 end -- default: front
  if type(side) == "string" then
    local n = sides[side:lower()]
    if not n then return nil, "unknown side: " .. side end
    return n
  elseif type(side) == "number" and side >= 0 and side <= 5 then
    return side
  end
  return nil, "invalid side"
end

-- #SEC M-14 — coerce a 1-based slot index. Rejects nil/NaN/string/zero/
-- negative/fractional values before they reach the robot proxy.
local function vSlot(n)
  n = tonumber(n)
  if not n or n ~= n then return nil, "invalid slot" end
  n = math.floor(n)
  if n < 1 then return nil, "invalid slot (must be >= 1)" end
  return n
end

-- ============================================================
-- Movement
-- ============================================================

--- Move forward.
function robot.forward()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(3)  -- front
end

--- Move backward.
function robot.back()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(2)  -- back
end

--- Move up.
function robot.up()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(1)  -- up/top
end

--- Move down.
function robot.down()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(0)  -- down/bottom
end

-- ============================================================
-- Turning
-- ============================================================

function robot.turnLeft()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.turn(false)
end

function robot.turnRight()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.turn(true)
end

-- ============================================================
-- Interaction
-- ============================================================

--- Swing (break block / attack entity).
-- @param side number|string  Side to swing at (default: front)
function robot.swing(side)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.swing(s)
end

--- Use (right-click / place).
-- @param side number|string  Side (default: front)
-- @param sneaking boolean    Sneak while using (default: false)
function robot.use(side, sneaking)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.use(s, sneaking or false)
end

--- Place block from selected inventory slot.
-- @param side number|string  Side (default: front)
function robot.place(side)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.place(s)
end

--- Detect block presence.
-- @param side number|string  Side (default: front)
-- @return boolean, string    true if block present, description
function robot.detect(side)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.detect(s)
end

-- ============================================================
-- Inventory management
-- ============================================================

--- Drop items from selected slot.
-- @param side number|string  Side to drop toward (default: front)
-- @param count number        Number to drop (default: all)
function robot.drop(side, count)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.drop(s, count or 64)
end

--- Pick up items.
-- @param side number|string  Side to suck from (default: front)
-- @param count number        Number to pick up (default: all)
function robot.suck(side, count)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.suck(s, count or 64)
end

--- Select an inventory slot.
-- @param slot number  Slot number (1-based)
function robot.select(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local vs, e = vSlot(slot); if not vs then return nil, e end  -- #SEC M-14
  return p.select(vs)
end

--- Get item count in a slot.
-- @param slot number  Slot number (default: selected)
function robot.count(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if slot ~= nil then
    local vs, e = vSlot(slot); if not vs then return nil, e end  -- #SEC M-14
    return p.count(vs)
  end
  return p.count(p.select())
end

--- Get free space in a slot.
-- @param slot number  Slot number (default: selected)
function robot.space(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if slot ~= nil then
    local vs, e = vSlot(slot); if not vs then return nil, e end  -- #SEC M-14
    return p.space(vs)
  end
  return p.space(p.select())
end

--- Get inventory size.
function robot.inventorySize()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.inventorySize()
end

--- Get a sequential table of non-empty inventory slots.
-- Returns { { slot=N, count=N, space=S }, ... }
function robot.inventory()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local size = p.inventorySize()
  local inv = {}
  for i = 1, size do
    local c = p.count(i)
    if c > 0 then
      inv[#inv + 1] = { slot = i, count = c, space = p.space(i) }
    end
  end
  return inv
end

-- ============================================================
-- Tool / Status
-- ============================================================

--- Get tool durability (0.0 - 1.0).
function robot.durability()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local ok, result = pcall(p.durabilityLevel)
  if not ok then return nil, "no tool equipped" end
  return result
end

--- Get robot name.
function robot.name()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.name()
end

--- Check if a robot component is available.
function robot.available()
  return getProxy() ~= nil
end

--- Refresh the proxy (useful after hot-plug).
function robot.refresh()
  proxy = nil
  return getProxy() ~= nil
end

return robot
