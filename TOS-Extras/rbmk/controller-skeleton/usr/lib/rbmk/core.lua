-- ╔══════════════════════════════════════════════════════════════╗
-- ║  rbmk.core — driver binding + SAFETY RULES (pure, no I/O)    ║
-- ║                                                              ║
-- ║  Two jobs, both deliberately hardware-free so they can be    ║
-- ║  unit-tested off-box (test_rbmk.lua):                        ║
-- ║                                                              ║
-- ║   1. DRIVER BINDING. HBM's Nuclear Tech Mod exposes its RBMK ║
-- ║      console through an OC component whose type name and     ║
-- ║      method surface we do NOT know for certain — Plan.md's   ║
-- ║      open question #1, answerable only by an in-game survey. ║
-- ║      So method names are DATA (a "profile"), not literals    ║
-- ║      baked into the controller. `rbmk survey` prints what a  ║
-- ║      real component actually offers; bind() then reports     ║
-- ║      exactly which profile entries resolved and which are    ║
-- ║      missing, so a wrong guess is a legible diagnostic       ║
-- ║      instead of a nil-index crash next to a reactor.         ║
-- ║                                                              ║
-- ║   2. SAFETY RULES. Given a telemetry snapshot and limits,    ║
-- ║      decide: ok / warn / SCRAM. This is the safety-critical  ║
-- ║      half of the add-on and it is pure arithmetic — it is    ║
-- ║      tested exhaustively here rather than in-world.          ║
-- ║                                                              ║
-- ║  DESIGN RULE (Plan.md §Safety): the controller is            ║
-- ║  authoritative, displays are strictly read-only, and NOTHING ║
-- ║  that arrives over the network may move a rod. v1 is         ║
-- ║  READ-ONLY + SCRAM (Plan.md open question #4): the only      ║
-- ║  write this code will ever emit is the shutdown.             ║
-- ╚══════════════════════════════════════════════════════════════╝

local C = {}

C.VERSION = "0.1.0"

-- ============================================================
-- Driver profiles
-- ============================================================
-- A profile maps the LOGICAL readings the controller needs onto whatever
-- the mod actually calls them. Every field is optional: a console that
-- can't report flux still gets temperature protection.
--
-- The shipped profiles are CANDIDATES, not confirmed API. Run
-- `rbmk survey` against a real console and correct /etc/rbmk.cfg —
-- that survey is the whole point of this indirection.

C.PROFILES = {
  -- Best-guess names, ordered most→least likely. The controller tries
  -- each candidate in turn and uses the first that exists on the proxy.
  ["hbm-generic"] = {
    componentTypes = { "rbmk_console", "rbmk_control", "ntm_rbmk_console" },
    temp     = { "getTemp", "getTemperature", "getCoreTemp" },
    flux     = { "getFlux", "getNeutronFlux" },
    rodDepth = { "getRodDepth", "getControlRodLevel", "getRods" },
    steam    = { "getSteam", "getSteamProduction" },
    water    = { "getWater", "getWaterLevel" },
    fuel     = { "getFuel", "getFuelLevel", "getCoreFuel" },
    -- The only write v1 performs.
    scram    = { "setAZ5", "scram", "az5", "shutdown" },
    -- Some builds expose everything as one table instead of getters.
    bulk     = { "getInfo", "getStats", "getData" },
  },
}

--- Resolve a profile against a live proxy's method list.
--- `methods` is a set OR array of method names available on the
--- component. Returns { bound = { logical = methodName }, missing = { … },
--- bulk = methodName|nil }. Pure — no component access.
function C.bind(profile, methods)
  local have = {}
  if type(methods) == "table" then
    for k, v in pairs(methods) do
      if type(k) == "string" then have[k] = true          -- set form
      elseif type(v) == "string" then have[v] = true end  -- array form
    end
  end
  local bound, missing = {}, {}
  local LOGICAL = { "temp", "flux", "rodDepth", "steam", "water", "fuel", "scram" }
  for _, logical in ipairs(LOGICAL) do
    local candidates = profile[logical] or {}
    local found
    for _, name in ipairs(candidates) do
      if have[name] then found = name; break end
    end
    if found then bound[logical] = found else missing[#missing + 1] = logical end
  end
  local bulk
  for _, name in ipairs(profile.bulk or {}) do
    if have[name] then bulk = name; break end
  end
  return { bound = bound, missing = missing, bulk = bulk }
end

--- Is a binding good enough to run a controller on? Temperature is the
--- floor: without it there is no protection worth the name, and we would
--- rather refuse to start than pretend to supervise a reactor.
--- SCRAM is separately required unless the operator has wired the
--- redstone AZ-5 backup (Plan.md §Safety rule 2).
function C.bindingUsable(binding, hasRedstoneScram)
  if not binding or not binding.bound then return false, "no binding" end
  if not (binding.bound.temp or binding.bulk) then
    return false, "no temperature reading — refusing to supervise blind"
  end
  if not (binding.bound.scram or hasRedstoneScram) then
    return false, "no SCRAM path (no console method and no redstone AZ-5)"
  end
  return true
end

-- ============================================================
-- Telemetry normalization
-- ============================================================

--- Normalize a raw reading table into the canonical shape the rest of
--- the add-on (and the display satellites) speak. Unknown fields are
--- dropped; numbers are coerced; nils stay nil (missing ≠ zero — a
--- missing temperature must never read as a cold reactor).
function C.normalize(raw)
  local t = {}
  local function num(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) end
    return nil
  end
  raw = raw or {}
  t.temp     = num(raw.temp)
  t.flux     = num(raw.flux)
  t.rodDepth = num(raw.rodDepth)
  t.steam    = num(raw.steam)
  t.water    = num(raw.water)
  t.fuel     = num(raw.fuel)
  return t
end

-- ============================================================
-- Safety rules
-- ============================================================

C.DEFAULT_LIMITS = {
  tempWarn   = 800,     -- °C — advisory
  tempScram  = 1000,    -- °C — automatic shutdown
  fluxWarn   = 8000,
  fluxScram  = 10000,
  waterMin   = 10,      -- % — starving the loop is a shutdown condition
  staleAfter = 5,       -- s without a fresh reading = lost the console
}

--- Evaluate a snapshot against limits.
--- Returns (level, reasons) where level is "ok" | "warn" | "scram" and
--- reasons is an array of human-readable strings — ALWAYS populated for
--- warn/scram so the log says WHY the reactor was shut down.
---
--- `age` is seconds since the reading was taken. A STALE reading is a
--- scram condition, not an "ok": losing the console while a reactor runs
--- is precisely when you want the rods in (Plan.md §Safety rule 3).
--- `missingTemp` likewise scrams — supervising blind is not supervising.
function C.evaluate(snap, limits, age)
  limits = limits or C.DEFAULT_LIMITS
  local reasons = {}
  local level = "ok"
  local function raise(to, why)
    reasons[#reasons + 1] = why
    if to == "scram" then level = "scram"
    elseif level ~= "scram" then level = "warn" end
  end

  if age ~= nil and limits.staleAfter and age > limits.staleAfter then
    raise("scram", string.format("telemetry stale (%.1fs > %.1fs)",
      age, limits.staleAfter))
  end

  snap = snap or {}
  if snap.temp == nil then
    raise("scram", "no temperature reading")
  else
    if limits.tempScram and snap.temp >= limits.tempScram then
      raise("scram", string.format("core %.0f >= scram limit %.0f",
        snap.temp, limits.tempScram))
    elseif limits.tempWarn and snap.temp >= limits.tempWarn then
      raise("warn", string.format("core %.0f >= warn limit %.0f",
        snap.temp, limits.tempWarn))
    end
  end

  if snap.flux ~= nil then
    if limits.fluxScram and snap.flux >= limits.fluxScram then
      raise("scram", string.format("flux %.0f >= scram limit %.0f",
        snap.flux, limits.fluxScram))
    elseif limits.fluxWarn and snap.flux >= limits.fluxWarn then
      raise("warn", string.format("flux %.0f >= warn limit %.0f",
        snap.flux, limits.fluxWarn))
    end
  end

  if snap.water ~= nil and limits.waterMin and snap.water < limits.waterMin then
    raise("scram", string.format("coolant %.0f%% < minimum %.0f%%",
      snap.water, limits.waterMin))
  end

  return level, reasons
end

--- Merge operator limits over the defaults, dropping anything that isn't
--- a positive number. A typo'd config must not silently disable a limit:
--- an unusable value falls back to the DEFAULT, never to "no limit".
function C.mergeLimits(cfg)
  local out = {}
  for k, v in pairs(C.DEFAULT_LIMITS) do out[k] = v end
  if type(cfg) ~= "table" then return out end
  for k, v in pairs(cfg) do
    if C.DEFAULT_LIMITS[k] ~= nil then
      local n = tonumber(v)
      if n and n > 0 then out[k] = n end
    end
  end
  return out
end

-- ============================================================
-- Telemetry frames (controller -> display satellites)
-- ============================================================

--- Build the broadcast frame. Read-only data by design: displays are
--- untrusted consumers, so this carries no control surface at all.
--- `seq` + `uptime` let a display show a loud STALE banner when frames
--- stop (Plan.md §Safety rule 3, the display half of the watchdog).
function C.frame(snap, level, seq, uptime, name)
  return {
    magic = "RBMK", v = 1,
    name = name or "rbmk",
    seq = seq or 0, uptime = uptime or 0,
    level = level or "ok",
    temp = snap and snap.temp, flux = snap and snap.flux,
    rodDepth = snap and snap.rodDepth, steam = snap and snap.steam,
    water = snap and snap.water, fuel = snap and snap.fuel,
  }
end

--- Validate an inbound frame on the display side. Returns (ok, why).
--- Rejects anything that isn't our magic/version, and — importantly —
--- ignores any field that would look like a command: a display that
--- honoured a "setRod" key in a telemetry frame would turn the
--- unauthenticated broadcast channel into reactor control.
function C.validateFrame(f)
  if type(f) ~= "table" then return false, "not a table" end
  if f.magic ~= "RBMK" then return false, "bad magic" end
  if f.v ~= 1 then return false, "unsupported version " .. tostring(f.v) end
  if type(f.seq) ~= "number" then return false, "no sequence" end
  for _, forbidden in ipairs({ "cmd", "command", "setRod", "rod", "scram", "exec" }) do
    if f[forbidden] ~= nil then
      return false, "frame carries a control field (" .. forbidden .. ") — refused"
    end
  end
  return true
end

--- Is a display's newest frame stale? Pure.
function C.frameStale(lastSeq, lastAt, now, staleAfter)
  if lastSeq == nil or lastAt == nil then return true end
  return (now - lastAt) > (staleAfter or C.DEFAULT_LIMITS.staleAfter)
end

return C
