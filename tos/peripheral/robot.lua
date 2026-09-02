local hal   = require("kernel.hal")
local sides = require("compat.sides")

local robot = {}
local proxy

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

local function getProxy()

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
  if side == nil then return 3 end
  if type(side) == "string" then
    local n = sides[side:lower()]
    if not n then return nil, "unknown side: " .. side end
    return n
  elseif type(side) == "number" and side >= 0 and side <= 5 then
    return side
  end
  return nil, "invalid side"
end

local function vSlot(n)
  n = tonumber(n)
  if not n or n ~= n then return nil, "invalid slot" end
  n = math.floor(n)
  if n < 1 then return nil, "invalid slot (must be >= 1)" end
  return n
end

function robot.forward()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(3)
end

function robot.back()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(2)
end

function robot.up()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(1)
end

function robot.down()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.move(0)
end

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

function robot.swing(side)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.swing(s)
end

function robot.use(side, sneaking)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.use(s, sneaking or false)
end

function robot.place(side)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.place(s)
end

function robot.detect(side)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.detect(s)
end

function robot.drop(side, count)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.drop(s, count or 64)
end

function robot.suck(side, count)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.suck(s, count or 64)
end

function robot.select(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local vs, e = vSlot(slot); if not vs then return nil, e end
  return p.select(vs)
end

function robot.count(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if slot ~= nil then
    local vs, e = vSlot(slot); if not vs then return nil, e end
    return p.count(vs)
  end
  return p.count(p.select())
end

function robot.space(slot)
  local p = getProxy()
  if not p then return nil, "no robot component" end
  if slot ~= nil then
    local vs, e = vSlot(slot); if not vs then return nil, e end
    return p.space(vs)
  end
  return p.space(p.select())
end

function robot.inventorySize()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.inventorySize()
end

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

function robot.durability()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  local ok, result = pcall(p.durabilityLevel)
  if not ok then return nil, "no tool equipped" end
  return result
end

function robot.name()
  local p = getProxy()
  if not p then return nil, "no robot component" end
  return p.name()
end

function robot.available()
  return getProxy() ~= nil
end

function robot.refresh()
  proxy = nil
  return getProxy() ~= nil
end

return robot
