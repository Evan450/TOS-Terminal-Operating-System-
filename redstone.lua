-- ╔══════════════════════════════════════╗
-- ║  TOS Peripheral - Redstone Control  ║
-- ╚══════════════════════════════════════╝

local hal   = require("kernel.hal")
local sides = require("compat.sides")

local rs = {}
local proxy  -- lazy-loaded redstone proxy

-- ============================================================
-- Internal helpers
-- ============================================================

local function getProxy()
  if not proxy then
    proxy = hal.proxy("redstone")
  end
  return proxy
end

--- Resolve a side value: accepts number 0-5 or string name.
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

--- Resolve a color value: accepts number or string name.
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

-- ============================================================
-- Basic redstone I/O
-- ============================================================

function rs.getInput(side)
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.getInput(s)
end

function rs.getOutput(side)
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.getOutput(s)
end

function rs.setOutput(side, value)
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  value = math.max(0, math.min(15, math.floor(value or 0)))
  p.setOutput(s, value)
  return true
end

function rs.getComparatorInput(side)
  local p = getProxy()
  if not p then return nil, "no redstone component" end
  local s, err = resolveSide(side)
  if not s then return nil, err end
  return p.getComparatorInput(s)
end

-- ============================================================
-- Bundled cable support
-- ============================================================

function rs.getBundledInput(side, color)
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

-- ============================================================
-- Utilities
-- ============================================================

--- Pulse a side: set output to 15, wait duration seconds, set to 0.
-- @param side number|string  Side to pulse
-- @param duration number     Seconds to hold (default 0.5)
function rs.pulse(side, duration)
  local ok, err = rs.setOutput(side, 15)
  if not ok then return nil, err end
  duration = duration or 0.5
  -- Use os.sleep if available, fall back to computer.pullSignal
  if os.sleep then
    os.sleep(duration)
  else
    require("computer").pullSignal(duration)
  end
  rs.setOutput(side, 0)
  return true
end

--- Get a status table showing all 6 sides' input/output levels.
function rs.status()
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

--- Check if a redstone component is available.
function rs.available()
  return getProxy() ~= nil
end

--- Refresh the proxy (useful after hot-plug).
function rs.refresh()
  proxy = nil
  return getProxy() ~= nil
end

return rs
