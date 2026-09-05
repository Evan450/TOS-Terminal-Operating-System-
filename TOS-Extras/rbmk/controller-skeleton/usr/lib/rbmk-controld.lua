-- ╔══════════════════════════════════════════════════════════════╗
-- ║  rbmk-controld — the supervising service                     ║
-- ║                                                              ║
-- ║  Polls the console, evaluates the safety rules, broadcasts   ║
-- ║  telemetry to display satellites, and owns SCRAM.            ║
-- ║                                                              ║
-- ║  Plan.md §Safety, implemented:                               ║
-- ║   1. The controller is authoritative. Nothing inbound moves  ║
-- ║      anything — this service registers NO network receive    ║
-- ║      handler at all. Displays are broadcast-only consumers.  ║
-- ║   2. SCRAM works with the network down: the trigger is the   ║
-- ║      local poll loop, and the action is a local console      ║
-- ║      method and/or a hard-wired redstone AZ-5 line.          ║
-- ║   3. Watchdog both ways: frames carry seq + uptime so a      ║
-- ║      display can show STALE; here, a reading that goes       ║
-- ║      missing or stale is itself a SCRAM condition.           ║
-- ║   4. Limits live in /etc/rbmk.cfg, admin-edited only.        ║
-- ║                                                              ║
-- ║  UNVERIFIED AGAINST THE REAL MOD: the console binding comes  ║
-- ║  from a survey-driven profile (Plan.md open question #1). If ║
-- ║  the binding is unusable the service REFUSES TO START rather ║
-- ║  than idling next to an unsupervised reactor.                ║
-- ╚══════════════════════════════════════════════════════════════╝

local core = require("rbmk.core")
local cmd  = require("rbmk-cmd")

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
-- _lastLevel belongs here with the rest: without the `local` it was a plain
-- GLOBAL, written into whatever environment the service happened to be
-- loaded under. (test_rbmk.lua)
local _seq, _lastGood, _scrammed, _lastLevel = 0, nil, false, nil

local function broadcast(frame)
  -- Telemetry is READ-ONLY data for untrusted displays, so it rides a
  -- plain broadcast — no trust secret needed, and none is spent. The
  -- mesh transport is not used: telemetry is high-rate, local, and
  -- worthless to relay or retry (a stale frame is worse than none).
  local net = firstRequire("kernel.net")
  if not (net and net.broadcast and net.getProtocol) then return end
  local ok, protocol = pcall(function() return net.getProtocol() end)
  if not ok or not protocol then return end
  -- Reuse the generic MSG type; displays filter on the RBMK magic.
  local t = protocol.TYPE and (protocol.TYPE.MSG or protocol.TYPE.PING)
  if not t then return end
  pcall(net.broadcast, protocol.makePacket(t, frame))
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
  -- Audible: the operator may not be looking at a screen.
  if computer and computer.beep then
    pcall(computer.beep, 1400, 0.2); pcall(computer.beep, 1000, 0.4)
  end
end

local function tick()
  if not _running then return end
  local now = computer and computer.uptime() or 0
  local snap = cmd.read(_proxy, _binding)
  local age
  if snap.temp ~= nil then
    _lastGood = now
    age = 0
  else
    age = _lastGood and (now - _lastGood) or (_limits.staleAfter + 1)
  end

  local level, reasons = core.evaluate(snap, _limits, age)
  _seq = _seq + 1
  broadcast(core.frame(snap, level, _seq, now, _cfg.name))

  if level == "scram" then
    fireScram(table.concat(reasons, "; "))
  elseif level == "warn" then
    -- Warn once per transition, not once per poll — a 1 Hz log flood
    -- would bury the entry that matters.
    if _lastLevel ~= "warn" then
      log.warn(LOG, "warning: " .. table.concat(reasons, "; "))
    end
  elseif _scrammed and level == "ok" then
    -- Latch cleared only by the operator restarting the service: an
    -- automatic un-SCRAM is never correct.
    log.info(LOG, "conditions normal (SCRAM latch still set — restart to clear)")
  end
  _lastLevel = level
end

function D.start()
  if _running then return true end
  _cfg = cmd.loadCfg()
  _limits = core.mergeLimits(_cfg.limits)
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
    -- Refusing to start is the safe failure: a service that "runs" but
    -- can't read a temperature or fire a SCRAM is worse than an absent
    -- one, because the operator believes they are supervised.
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

--- Snapshot for `rbmk status` / diagnostics.
function D.state()
  return { running = _running, seq = _seq, scrammed = _scrammed,
           level = _lastLevel, binding = _binding }
end

return D
