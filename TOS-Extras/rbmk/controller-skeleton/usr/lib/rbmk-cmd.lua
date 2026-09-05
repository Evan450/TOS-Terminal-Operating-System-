-- ╔══════════════════════════════════════════════════════════════╗
-- ║  `rbmk` — operator command for the RBMK controller           ║
-- ║                                                              ║
-- ║    rbmk survey            enumerate candidate components +   ║
-- ║                           their ACTUAL method surface, and   ║
-- ║                           report how the profile binds       ║
-- ║    rbmk status            live reading + safety evaluation   ║
-- ║    rbmk limits            show the active limits             ║
-- ║    rbmk scram             manual shutdown (admin)            ║
-- ║                                                              ║
-- ║  `survey` is the important one and the reason this add-on    ║
-- ║  exists in this shape: HBM's OC method names are Plan.md's   ║
-- ║  open question #1. Rather than hard-code a guess, the        ║
-- ║  controller reads them from /etc/rbmk.cfg and this command   ║
-- ║  tells the operator exactly what to put there.               ║
-- ║                                                              ║
-- ║  Full-priv library (loaded by the base shell / rc via the    ║
-- ║  real require), so kernel.* is available here.               ║
-- ╚══════════════════════════════════════════════════════════════╝

local core = require("rbmk.core")

local M = {}

local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end
local component = firstRequire("component")
local fs        = firstRequire("kernel.fs", "filesystem")

local CFG_PATH = "/etc/rbmk.cfg"

-- ── Config ─────────────────────────────────────────────────────────
-- fs.readFile + text-only load (never `loadfile`: at rc time that
-- global doesn't exist — the cluster lesson).
local function loadCfg()
  local cfg = {}
  if fs and fs.exists and fs.exists(CFG_PATH) and fs.readFile then
    local src = fs.readFile(CFG_PATH)
    local chunk = src and load(src, "=" .. CFG_PATH, "t", {})
    if chunk then
      local ok, res = pcall(chunk)
      if ok and type(res) == "table" then cfg = res end
    end
  end
  return cfg
end
M.loadCfg = loadCfg

local function activeProfile(cfg)
  -- An operator-supplied profile (post-survey) always wins over the
  -- shipped candidates.
  if type(cfg.profile) == "table" then return cfg.profile end
  return core.PROFILES[cfg.profileName or "hbm-generic"]
    or core.PROFILES["hbm-generic"]
end
M.activeProfile = activeProfile

-- ── Component discovery ────────────────────────────────────────────
-- Any component whose type LOOKS like a reactor console. Deliberately
-- broad: we don't know the real type name, so we surface candidates and
-- let the operator confirm rather than silently finding nothing.
local function candidates(profile)
  local out = {}
  if not (component and component.list) then return out end
  local want = {}
  for _, t in ipairs((profile and profile.componentTypes) or {}) do
    want[t:lower()] = true
  end
  for addr, ctype in component.list() do
    local lc = tostring(ctype):lower()
    local hit = want[lc]
    if not hit then
      -- Fuzzy: anything mentioning rbmk / reactor / nuclear is worth showing.
      hit = lc:find("rbmk", 1, true) or lc:find("reactor", 1, true)
        or lc:find("nuclear", 1, true) or lc:find("ntm", 1, true)
    end
    if hit then out[#out + 1] = { address = addr, type = ctype } end
  end
  return out
end
M.candidates = candidates

-- The method list of a live component. OC exposes this via
-- component.methods(addr) — NOT by iterating a proxy (a proxy's fields
-- are callables whose names you can read, but methods() is the
-- documented surface and the one that works for data-card-style
-- components; see the kernel's own tier-detection note).
local function methodsOf(addr)
  local names = {}
  if component and component.methods then
    local ok, m = pcall(component.methods, addr)
    if ok and type(m) == "table" then
      for k, v in pairs(m) do
        if type(k) == "string" then names[#names + 1] = k
        elseif type(v) == "string" then names[#names + 1] = v end
      end
    end
  end
  if #names == 0 and component and component.proxy then
    local ok, px = pcall(component.proxy, addr)
    if ok and type(px) == "table" then
      for k, v in pairs(px) do
        if type(v) == "function" and type(k) == "string" then
          names[#names + 1] = k
        end
      end
    end
  end
  table.sort(names)
  return names
end
M.methodsOf = methodsOf

-- ── Reading telemetry ──────────────────────────────────────────────
--- Read a snapshot through a binding. Every call is pcall'd: a console
--- that vanishes mid-poll must produce a MISSING reading (which the
--- safety rules treat as a scram condition), never an unhandled error
--- inside the control loop.
function M.read(proxy, binding)
  local raw = {}
  if binding.bulk then
    local ok, t = pcall(proxy[binding.bulk])
    if ok and type(t) == "table" then
      for k, v in pairs(t) do raw[k] = v end
    end
  end
  for logical, method in pairs(binding.bound or {}) do
    if logical ~= "scram" and proxy[method] then
      local ok, v = pcall(proxy[method])
      if ok and v ~= nil then raw[logical] = v end
    end
  end
  return core.normalize(raw)
end

--- Fire the shutdown. Returns (ok, how). Tries the console method, then
--- the redstone AZ-5 backup line — Plan.md §Safety rule 2 requires SCRAM
--- to work with the network down, so both paths are local.
function M.scram(proxy, binding, cfg)
  local fired, how = false, {}
  if binding and binding.bound and binding.bound.scram and proxy then
    local m = proxy[binding.bound.scram]
    if m then
      local ok = pcall(m, true)
      if ok then fired = true; how[#how + 1] = "console." .. binding.bound.scram end
    end
  end
  local side = cfg and tonumber(cfg.az5RedstoneSide)
  if side and component and component.list then
    local rsAddr = component.list("redstone")()
    if rsAddr then
      local okP, rs = pcall(component.proxy, rsAddr)
      if okP and rs and rs.setOutput then
        local ok = pcall(rs.setOutput, side, 15)
        if ok then fired = true; how[#how + 1] = "redstone side " .. side end
      end
    end
  end
  return fired, table.concat(how, " + ")
end

-- ── Command entry ──────────────────────────────────────────────────

function M.run(args, o)
  o = o or print
  args = args or {}
  local sub = (args[1] or "status"):lower()
  local cfg = loadCfg()
  local profile = activeProfile(cfg)

  if sub == "survey" then
    o("RBMK component survey", 0x00AAFF)
    o("")
    local cands = candidates(profile)
    if #cands == 0 then
      o("No candidate components found.", 0xFF6600)
      o("Looked for the profile's types plus anything matching", 0xAAAAAA)
      o("rbmk / reactor / nuclear / ntm. Is the console adapter linked?", 0xAAAAAA)
      return
    end
    for _, c in ipairs(cands) do
      o(string.format("%s  %s", tostring(c.address):sub(1, 8), tostring(c.type)), 0xFFFFFF)
      local names = methodsOf(c.address)
      if #names == 0 then
        o("    (no methods visible)", 0xAAAAAA)
      else
        -- Print the real surface: this is the answer to open question #1.
        local line = "    "
        for _, n in ipairs(names) do
          if #line + #n + 2 > 76 then o(line, 0xAAAAAA); line = "    " end
          line = line .. n .. "  "
        end
        if #line > 4 then o(line, 0xAAAAAA) end
      end
      local binding = core.bind(profile, names)
      local boundList = {}
      for logical, method in pairs(binding.bound) do
        boundList[#boundList + 1] = logical .. "=" .. method
      end
      table.sort(boundList)
      o("    bound:   " .. (#boundList > 0 and table.concat(boundList, "  ") or "(nothing)"),
        #boundList > 0 and 0x00FF00 or 0xFF6600)
      if #binding.missing > 0 then
        o("    missing: " .. table.concat(binding.missing, "  "), 0xFFAA00)
      end
      if binding.bulk then o("    bulk:    " .. binding.bulk, 0x00FF00) end
      local usable, why = core.bindingUsable(binding, cfg.az5RedstoneSide ~= nil)
      o("    usable:  " .. (usable and "YES" or ("NO — " .. tostring(why))),
        usable and 0x00FF00 or 0xFF0000)
      o("")
    end
    o("If a reading is missing, add the real method name to " .. CFG_PATH, 0xAAAAAA)
    o("under profile = { temp = { \"theRealName\" }, ... } and re-run.", 0xAAAAAA)
    return
  end

  if sub == "limits" then
    local lim = core.mergeLimits(cfg.limits)
    o("Active safety limits:", 0x00AAFF)
    local keys = {}
    for k in pairs(lim) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      o(string.format("  %-12s %s", k, tostring(lim[k])), 0xFFFFFF)
    end
    o("Edit " .. CFG_PATH .. " (admin) to change them.", 0xAAAAAA)
    return
  end

  -- status / scram both need a bound console.
  local cands = candidates(profile)
  if #cands == 0 then
    o("No RBMK console found — run `rbmk survey`.", 0xFF6600); return
  end
  local target = cands[1]
  if cfg.address then
    for _, c in ipairs(cands) do
      if tostring(c.address):sub(1, #cfg.address) == cfg.address then target = c end
    end
  end
  local names = methodsOf(target.address)
  local binding = core.bind(profile, names)
  local okP, proxy = pcall(component.proxy, target.address)
  if not okP or not proxy then o("Cannot open the console proxy.", 0xFF0000); return end

  if sub == "scram" then
    -- Manual SCRAM is deliberately available to anyone at the console:
    -- an emergency stop that asks for credentials is not an emergency
    -- stop. Every firing is logged by the service.
    local fired, how = M.scram(proxy, binding, cfg)
    if fired then o("SCRAM fired (" .. how .. ")", 0xFF0000)
    else o("SCRAM FAILED — no console method and no redstone AZ-5 line.", 0xFF0000) end
    return
  end

  local snap = M.read(proxy, binding)
  local lim = core.mergeLimits(cfg.limits)
  local level, reasons = core.evaluate(snap, lim, 0)
  o("RBMK " .. tostring(target.type) .. "  " .. tostring(target.address):sub(1, 8),
    0x00AAFF)
  local function row(label, v, unit)
    if v == nil then o(string.format("  %-10s (not reported)", label), 0xAAAAAA)
    else o(string.format("  %-10s %s%s", label, tostring(v), unit or ""), 0xFFFFFF) end
  end
  row("core", snap.temp, " C")
  row("flux", snap.flux)
  row("rods", snap.rodDepth)
  row("steam", snap.steam)
  row("water", snap.water, " %")
  row("fuel", snap.fuel)
  local col = (level == "scram") and 0xFF0000
    or (level == "warn") and 0xFFAA00 or 0x00FF00
  o("  state      " .. level:upper(), col)
  for _, r in ipairs(reasons) do o("    - " .. r, col) end
end

return M
