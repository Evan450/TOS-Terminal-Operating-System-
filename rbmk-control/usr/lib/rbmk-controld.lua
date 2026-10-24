























local core  = require("rbmk.core")
local cmd   = require("rbmk-cmd")



local skala = require("rbmk.skala")

local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end
local component = firstRequire("component")
local computer  = firstRequire("computer")
local event     = firstRequire("kernel.event", "event")
local log
do
  local m = firstRequire("kernel.log", "log")
  if m and m.info then log = m
  else log = { info = function() end, warn = function() end, error = function() end } end
end
local LOG = "rbmk"

local D = {}

local _running = false
local _timer, _proxy, _binding, _cfg, _limits




local _grid, _nextMap, _packedCols



local _seq, _lastGood, _scrammed, _lastLevel = 0, nil, false, nil















local _modems, _port
local function broadcast(frame)
  if not _modems then
    _modems, _port = {}, tonumber(_cfg and _cfg.telemetryPort) or core.TELEMETRY_PORT
    if component and component.list then
      for addr in component.list("modem") do
        local ok, m = pcall(component.proxy, addr)
        if ok and m and m.broadcast then _modems[#_modems + 1] = m end
      end
    end
    if #_modems == 0 then
      log.warn(LOG, "no modem: supervising locally, but no display can see this")
    else
      log.info(LOG, string.format("telemetry on port %d (%d modem%s)",
        _port, #_modems, #_modems == 1 and "" or "s"))
    end
  end
  if #_modems == 0 then return end
  local a = core.encodeWire(frame)
  for _, m in ipairs(_modems) do
    pcall(m.broadcast, _port, a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9])
  end
end

local function fireScram(why)
  if _scrammed then return end
  local fired, how = cmd.scram(_proxy, _binding, _cfg)
  _scrammed = true
  if fired then
    log.error(LOG, "SCRAM fired (" .. tostring(how) .. "): " .. tostring(why))
  else
    log.error(LOG, "SCRAM REQUESTED BUT NO PATH WORKED: " .. tostring(why))
  end
  
  if computer and computer.beep then
    pcall(computer.beep, 1400, 0.2); pcall(computer.beep, 1000, 0.4)
  end
end

local function tick()
  if not _running then return end
  local now = computer and computer.uptime() or 0
  local snap, scanned = cmd.read(_proxy, _binding)
  local age
  if snap.temp ~= nil then
    _lastGood = now
    age = 0
  else
    age = _lastGood and (now - _lastGood) or (_limits.staleAfter + 1)
  end

  local level, reasons = core.evaluate(snap, _limits, age)
  _seq = _seq + 1

  --! The core map is throttled independently of the safety poll. The
  --! safety loop must run as often as the operator asked; the map is a
  --! picture, and re-reading 225 channels four times a second spends
  --! the machine's per-tick component budget on something no human can
  --! read that fast. Safety NEVER waits on this: `snap` above is read
  --! every tick regardless, and evaluate() runs on `snap` alone.
  if now >= (_nextMap or 0) then
    _nextMap = now + (tonumber(_cfg.mapInterval) or 1)
    --! The NTM driver's single scan already produced the channels; only
    --! a getter-style console needs a second pass for the picture.
    local cols = scanned or cmd.readColumns(_proxy, _binding, _grid)
    _packedCols = (#cols > 0) and core.packColumns(cols, _grid, skala.PARAMS) or nil
  end

  broadcast(core.frame(snap, level, _seq, now, _cfg.name, _packedCols, reasons))

  if level == "scram" then
    fireScram(table.concat(reasons, "; "))
  elseif level == "warn" then
    
    
    if _lastLevel ~= "warn" then
      log.warn(LOG, "warning: " .. table.concat(reasons, "; "))
    end
  elseif _scrammed and level == "ok" then
    
    
    log.info(LOG, "conditions normal (SCRAM latch still set — restart to clear)")
  end
  _lastLevel = level
end

function D.start()
  if _running then return true end
  _cfg = cmd.loadCfg()
  _limits = core.mergeLimits(_cfg.limits)
  _grid = core.mergeGrid(_cfg.grid)
  --! Dropped so the next broadcast re-reads the modem list and the
  --! configured port. A service restarted after the operator edited
  --! /etc/rbmk.cfg (or plugged a card in) must pick both up.
  _modems, _nextMap, _packedCols = nil, 0, nil
  local profile = cmd.activeProfile(_cfg)

  local cands = cmd.candidates(profile)
  if #cands == 0 then
    log.error(LOG, "no RBMK console component found — run `rbmk survey`")
    return false, "no console found"
  end
  local target = cands[1]
  if _cfg.address then
    for _, c in ipairs(cands) do
      if tostring(c.address):sub(1, #_cfg.address) == _cfg.address then target = c end
    end
  end
  local names = cmd.methodsOf(target.address)
  _binding = core.bind(profile, names)

  local usable, why = core.bindingUsable(_binding, _cfg.az5RedstoneSide ~= nil)
  if not usable then
    
    
    
    log.error(LOG, "refusing to start: " .. tostring(why)
      .. " (run `rbmk survey` and fix /etc/rbmk.cfg)")
    return false, why
  end

  local okP, proxy = pcall(component.proxy, target.address)
  if not okP or not proxy then
    log.error(LOG, "cannot open the console proxy")
    return false, "proxy failed"
  end
  _proxy = proxy
  _seq, _scrammed, _lastGood, _lastLevel = 0, false, nil, nil

  local interval = tonumber(_cfg.pollInterval) or 1
  if interval < 0.25 then interval = 0.25 end
  _timer = event and event.interval and event.interval(interval, tick, "rbmk.poll")
  _running = true
  log.info(LOG, string.format("supervising %s (%s) every %.2fs",
    tostring(target.type), tostring(target.address):sub(1, 8), interval))
  return true
end

function D.stop()
  if not _running then return true end
  if _timer and event and event.cancelTimer then pcall(event.cancelTimer, _timer) end
  _timer, _running = nil, false
  log.info(LOG, "stopped (reactor is NO LONGER SUPERVISED)")
  return true
end

function D.running() return _running end


function D.state()
  return { running = _running, seq = _seq, scrammed = _scrammed,
           level = _lastLevel, binding = _binding }
end

return D
