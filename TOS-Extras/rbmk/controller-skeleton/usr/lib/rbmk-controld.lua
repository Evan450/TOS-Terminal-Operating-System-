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

local core  = require("rbmk.core")
local cmd   = require("rbmk-cmd")
-- Only for PARAMS: the packed core map has to be encoded in the same
-- field order the panel decodes it in, and that order is defined once,
-- in rbmk.skala. No drawing happens here.
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
-- Core-map state. Declared here with the rest for the reason the note
-- below records: an undeclared name here is a GLOBAL in whatever
-- environment the service was loaded under, and test_rbmk.lua checks
-- for exactly that.
local _grid, _nextMap, _packedCols
-- _lastLevel belongs here with the rest: without the `local` it was a plain
-- GLOBAL, written into whatever environment the service happened to be
-- loaded under. (test_rbmk.lua)
local _seq, _lastGood, _scrammed, _lastLevel = 0, nil, false, nil

-- ── Telemetry out ──────────────────────────────────────────────────
-- #FIX — this used to go out as a TOS protocol MSG packet. That was
-- unreachable by construction: net/trust.lua's PERMISSIONS table allows
-- `msg` only at TRUSTED, and displays are UNTRUSTED BY DESIGN
-- (Plan.md §Protocol) — so every satellite dropped every frame at the
-- trust gate. OpenOS satellites could not have read it either;
-- net/protocol.lua's own header says TOS machines only talk to TOS
-- machines. Nothing caught it because the display half did not exist.
--
-- Now: a RAW MODEM BROADCAST of fixed primitive arguments on
-- core.TELEMETRY_PORT. Still strictly one-way — the controller never
-- opens the port, so this remains a machine with no inbound network
-- path (§Safety rule 1). The mesh is still not used: telemetry is
-- high-rate and local, and a relayed stale frame is worse than none.
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

  --! The core map is throttled independently of the safety poll. The
  --! safety loop must run as often as the operator asked; the map is a
  --! picture, and re-reading 225 channels four times a second spends
  --! the machine's per-tick component budget on something no human can
  --! read that fast. Safety NEVER waits on this: `snap` above is read
  --! every tick regardless, and evaluate() runs on `snap` alone.
  if now >= (_nextMap or 0) then
    _nextMap = now + (tonumber(_cfg.mapInterval) or 1)
    local cols = cmd.readColumns(_proxy, _binding, _grid)
    _packedCols = (#cols > 0) and core.packColumns(cols, _grid, skala.PARAMS) or nil
  end

  broadcast(core.frame(snap, level, _seq, now, _cfg.name, _packedCols, reasons))

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
