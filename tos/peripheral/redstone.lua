local hal   = require("kernel.hal")
local sides = require("compat.sides")

local rs = {}
local proxy

do
  local okE, eventMod = pcall(require, "kernel.event")
  if okE and eventMod and eventMod.on then
    local function reset(_, addr, ctype)
      if ctype == "redstone" then proxy = nil end
    end
    eventMod.on("component_removed", reset, "peripheral.redstone")
    eventMod.on("component_added",   reset, "peripheral.redstone")
  end
end

local function requireCap()
  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.current then
    local cur = procMod.current()

    if not cur then return true end
    if cur.caps and cur.caps["peripheral.redstone"] then return true end
    return false, "peripheral.redstone cap required"
  end
  return true
end

local function getProxy()

  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.current then
    local cur = procMod.current()
    if cur and not (cur.caps and cur.caps["peripheral.redstone"]) then
      return nil
    end
  end
  if not proxy then
    proxy = hal.proxy("redstone")
  end
  return proxy
end

local function resolveSide(side)
  if type(side) == "string" then
    local n = sides[side:lower()]
    if not n then return nil, "unknown side: " .. side end
    return n
  elseif type(side) == "number" and side >= 0 and side <= 5 then
    return side
  end
  return nil, "invalid side (expected 0-5 or name)"
end

local function resolveColor(color)
  if type(color) == "number" then return color end
  if type(color) == "string" then
    local ok, colors = pcall(require, "compat.colors")
    if ok and colors[color:lower()] then
      return colors[color:lower()]
    end
    return nil, "unknown color: " .. color
  end
  return nil, "invalid color"
end

function rs.getInput(side)
  local ok, err = requireCap(); if not ok then return nil, err end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err2 = resolveSide(side)
  if not s then return nil, err2 end
  return p.getInput(s)
end

function rs.getOutput(side)
  local ok, err = requireCap(); if not ok then return nil, err end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err2 = resolveSide(side)
  if not s then return nil, err2 end
  return p.getOutput(s)
end

function rs.setOutput(side, value)
  local ok, err = requireCap(); if not ok then return nil, err end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  value = math.max(0, math.min(15, math.floor(value or 0)))
  p.setOutput(s, value)
  return true
end

function rs.getComparatorInput(side)
  local ok, capErr = requireCap(); if not ok then return nil, capErr end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.getComparatorInput(s)
end

function rs.getBundledInput(side, color)
  local ok, capErr = requireCap(); if not ok then return nil, capErr end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local c, cerr = resolveColor(color)
  if not c then return nil, cerr end
  local ok, result = pcall(p.getBundledInput, s, c)
  if not ok then return nil, "bundled not supported" end
  return result
end

function rs.getBundledOutput(side, color)
  local ok, capErr = requireCap(); if not ok then return nil, capErr end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local c, cerr = resolveColor(color)
  if not c then return nil, cerr end
  local ok, result = pcall(p.getBundledOutput, s, c)
  if not ok then return nil, "bundled not supported" end
  return result
end

function rs.setBundledOutput(side, color, value)
  local ok, capErr = requireCap(); if not ok then return nil, capErr end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  local c, cerr = resolveColor(color)
  if not c then return nil, cerr end
  value = math.max(0, math.min(255, math.floor(value or 0)))
  local ok, result = pcall(p.setBundledOutput, s, c, value)
  if not ok then return nil, "bundled not supported" end
  return true
end

function rs.pulse(side, duration)

  local MAX_PULSE = 30
  duration = tonumber(duration) or 0.5
  if duration ~= duration then duration = 0.5 end
  if duration < 0 then duration = 0 end
  if duration > MAX_PULSE then duration = MAX_PULSE end

  local ok, err = rs.setOutput(side, 15)
  if not ok then return nil, err end

  if os.sleep then
    os.sleep(duration)
  else
    require("computer").pullSignal(duration)
  end
  rs.setOutput(side, 0)
  return true
end

function rs.status()
  local ok, capErr = requireCap(); if not ok then return nil, capErr end
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local sideNames = {"bottom", "top", "back", "front", "right", "left"}
  local result = {}
  for i = 0, 5 do
    result[#result + 1] = {
      name   = sideNames[i + 1],
      input  = p.getInput(i),
      output = p.getOutput(i),
    }
  end
  return result
end

function rs.available()
  return getProxy() ~= nil
end

function rs.refresh()
  proxy = nil
  return getProxy() ~= nil
end

return rs
