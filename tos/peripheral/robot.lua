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

--! #BUG (compat round, 2026-09-20) — WHAT THE MOD ACTUALLY TAKES. Checked
--! against OpenComputers' own Agent.scala @Callback docs, which are the
--! only authority here:
--!   swing(side:number[, face:number=side[, sneaky:boolean=false]])
--!   use  (side:number[, face:number=side[, sneaky:boolean=false
--!                                        [, duration:number=0]]])
--!   place(side:number[, face:number=side[, sneaky:boolean=false]])
--! `face` is a NUMBER (a finer click target on the block, defaulting to the
--! side) and `sneaky` is the boolean AFTER it. robot.use passed `sneaking`
--! in slot 2 — a boolean where the mod checks for an integer — and because
--! it wrote `sneaking or false`, it passed `false` there on EVERY call,
--! including calls that named no sneaking at all. So `use` raised a bad-
--! argument error on a real robot whatever you asked it, and the off-box
--! tests could not see it: a mock proxy accepts any argument list.
--!   Fixed by never putting a boolean in the face slot. `face` is optional
--! and resolved like any other side; when nothing needs slots 2+ we pass
--! the side alone and let the mod apply its own defaults.
local function faceArg(face)
  if face == nil then return nil end
  return resolveSide(face)
end

--- Swing (break block / attack entity).
-- @param side number|string  Side to swing at (default: front)
-- @param face number|string  Finer click target (default: same as side)
-- @param sneaky boolean      Sneak while swinging (default: false)
function robot.swing(side, face, sneaky)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local f, ferr = faceArg(face)
  if face ~= nil and not f then return nil, ferr end
  if f or sneaky then return p.swing(s, f or s, sneaky and true or false) end
  return p.swing(s)
end

--- Use (right-click).
-- @param side number|string  Side (default: front)
-- @param sneaking boolean    Sneak while using (default: false)
-- @param face number|string  Finer click target (default: same as side)
-- @param duration number     Hold the click this long, seconds (default: 0)
--! Argument ORDER departs from the mod's on purpose: `sneaking` has been
--! this function's second parameter since it was written, and moving it
--! would silently change the meaning of every existing call. face and
--! duration are appended instead. compat/robot.lua reorders for the
--! OpenOS-shaped API.
function robot.use(side, sneaking, face, duration)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local f, ferr = faceArg(face)
  if face ~= nil and not f then return nil, ferr end
  if duration ~= nil then
    local d = tonumber(duration)
    if not d or d ~= d or d < 0 then return nil, "invalid duration" end
    return p.use(s, f or s, sneaking and true or false, d)
  end
  if f or sneaking then return p.use(s, f or s, sneaking and true or false) end
  return p.use(s)
end

--- Place block from selected inventory slot.
-- @param side number|string  Side (default: front)
-- @param face number|string  Finer click target (default: same as side)
-- @param sneaky boolean      Sneak while placing (default: false)
function robot.place(side, face, sneaky)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local f, ferr = faceArg(face)
  if face ~= nil and not f then return nil, ferr end
  if f or sneaky then return p.place(s, f or s, sneaky and true or false) end
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

--- Select an inventory slot, or read which one is selected.
-- @param slot number  Slot number (1-based). Omit to read the current slot.
--! Omitting the slot used to return nil, "invalid slot". The mod's own
--! select() answers with the CURRENT slot when called with no argument, and
--! `robot.select()` is how an OpenOS program asks "which slot am I on" —
--! count() below has always relied on that raw behaviour internally. A
--! caller that passed nil got an error before and gets the slot number
--! now; nothing in the tree passed nil.
function robot.select(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if slot == nil then return p.select() end
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
--! #BUG (compat round, 2026-09-20) — the method is `durability`. There is
--! no `durabilityLevel` anywhere in OpenComputers: the callbacks on
--! Robot.scala/Agent.scala are durability, name, move, turn, swing, use,
--! place, detect, drop, suck, select, count, space, inventorySize,
--! compare, compareTo, transferTo, tankCount, tankLevel, tankSpace,
--! selectTank, get/setLightColor. So the pcall here ALWAYS failed on real
--! hardware and every robot reported "no tool equipped" — including robots
--! holding a tool. Off-box tests pass either way because a mock proxy
--! answers to any method name.
--!   The "no tool equipped" message is kept for the case it was written
--! for: the mod returns nil plus a reason when the tool slot is empty.
--! A missing METHOD is now reported as itself rather than mistranslated.
function robot.durability()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if type(p.durability) ~= "function" then
    return nil, "robot component has no durability()"
  end
  local ok, result, reason = pcall(p.durability)
  if not ok then return nil, tostring(result) end
  if result == nil then return nil, reason or "no tool equipped" end
  return result
end

-- ============================================================
-- Comparison and transfer
-- ============================================================

--- Compare the block on `side` with the selected slot's item.
-- @param side number|string  Side (default: front)
function robot.compare(side)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.compare(s)
end

--- Compare the selected slot with another slot.
-- @param slot number  Slot to compare against (1-based)
function robot.compareTo(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local vs, e = vSlot(slot); if not vs then return nil, e end  -- #SEC M-14
  return p.compareTo(vs)
end

--- Move items from the selected slot into another slot.
-- @param slot number   Destination slot (1-based)
-- @param count number  How many (default: the whole stack)
function robot.transferTo(slot, count)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local vs, e = vSlot(slot); if not vs then return nil, e end  -- #SEC M-14
  if count ~= nil then
    local c = tonumber(count)
    if not c or c ~= c or c < 0 then return nil, "invalid count" end
    return p.transferTo(vs, math.floor(c))
  end
  return p.transferTo(vs)
end

-- ============================================================
-- Tanks (fluid upgrades)
-- ============================================================

--- Number of internal tanks.
function robot.tankCount()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.tankCount()
end

--- Select a tank.
function robot.selectTank(tank)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local vt, e = vSlot(tank); if not vt then return nil, "invalid tank" end
  return p.selectTank(vt)
end

--- Fluid amount in a tank (default: the selected one).
function robot.tankLevel(tank)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if tank ~= nil then
    local vt = vSlot(tank); if not vt then return nil, "invalid tank" end
    return p.tankLevel(vt)
  end
  return p.tankLevel()
end

--- Remaining space in a tank (default: the selected one).
function robot.tankSpace(tank)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if tank ~= nil then
    local vt = vSlot(tank); if not vt then return nil, "invalid tank" end
    return p.tankSpace(vt)
  end
  return p.tankSpace()
end

-- ============================================================
-- Status light
-- ============================================================

--- Read the robot's status-light colour (0xRRGGBB).
function robot.getLightColor()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.getLightColor()
end

--- Set the robot's status-light colour (0xRRGGBB).
function robot.setLightColor(value)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local v = tonumber(value)
  if not v or v ~= v then return nil, "invalid colour" end
  return p.setLightColor(math.floor(v))
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
