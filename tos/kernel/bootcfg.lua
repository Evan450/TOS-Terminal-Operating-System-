-- ╔═══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Boot Configuration                          ║
-- ║                                                           ║
-- ║  The "everything → nothing" boot spectrum, in config.     ║
-- ║  Read VERY early (init.lua, before the kernel config      ║
-- ║  module exists) and FAIL-SAFE: a missing/corrupt          ║
-- ║  /etc/boot.cfg can never brick boot — it falls back to    ║
-- ║  the `normal` profile.                                    ║
-- ║                                                           ║
-- ║  Two orthogonal axes (per the boot-reorg design):         ║
-- ║    profile   = WHAT LOADS  (minimal/normal/full/diag)     ║
-- ║    verbosity = WHAT IT SAYS while booting — a "muter",    ║
-- ║                NOT a behavior change (silent/splash/      ║
-- ║                text/verbose). For operators who want a    ║
-- ║                clean startup screen vs scrolling debug.   ║
-- ║    advanced  = per-feature toggles (override the profile) ║
-- ╚═══════════════════════════════════════════════════════════╝

local bootcfg = {}

local PATH = "/etc/boot.cfg"
local MAX_BYTES = 8192

-- ============================================================
-- Vocabulary
-- ============================================================

-- Optional subsystems the profile/advanced layer can gate. (Required
-- subsystems — fs, display, process, security/login — are never gated.)
local FEATURES = {
  "swap", "power", "net", "theme", "compat", "audio", "integrityCheck",
  -- JBOD disk pooling is OFF in every profile (pinned false below); it
  -- only loads when an operator flips advanced.jbod = true. Listed here so
  -- normalize() preserves the flag and the Boot Settings UI can toggle it.
  "jbod",
  -- Operator-request (Jul 2026): the boot stages that run THIRD-PARTY or
  -- scheduled code are now gateable too — that's what makes `safe` a real
  -- Safe Mode instead of just a quiet one:
  --   services  = /etc/rc.d startup scripts (+ the restart supervisor)
  --   cron      = the cron scheduler
  --   packages  = package COMMAND DISPATCH (pkg admin verbs — list,
  --               install, uninstall, enable/disable — always work, so
  --               Safe Mode can still remove a broken add-on; only
  --               running package-provided commands is blocked)
  "services", "cron", "packages",
}
bootcfg.FEATURES = FEATURES

-- Profiles: `features` pins what loads (true=load, false=skip); an absent
-- key means "follow the RAM gate" (today's behavior). `verbosity` is the
-- profile's default muter level (overridable by an explicit cfg.verbosity).
local PROFILES = {
  minimal = {
    description = "Bare shell — skip every optional subsystem",
    verbosity = "splash",
    features = { swap = false, power = false, net = false, theme = false,
                 compat = false, audio = false, integrityCheck = false,
                 jbod = false, services = false, cron = false,
                 packages = false },
  },
  normal = {
    description = "Default — optional subsystems load if RAM allows",
    verbosity = "text",
    -- All RAM-gated, as TOS boots today — except jbod, which is a niche
    -- storage feature kept off unless explicitly enabled.
    features = { jbod = false },
  },
  full = {
    description = "Load every available subsystem (RAM permitting)",
    verbosity = "text",
    -- Even `full` leaves jbod off: pooling reshapes the mount tree, so it
    -- should be a deliberate operator choice, not a side effect of profile.
    features = { swap = true, power = true, net = true, theme = true,
                 compat = true, audio = true, integrityCheck = false,
                 jbod = false, services = true, cron = true,
                 packages = true },
  },
  diagnostic = {
    description = "Full + integrity check + verbose boot log",
    verbosity = "verbose",
    features = { swap = true, power = true, net = true, theme = true,
                 compat = true, audio = true, integrityCheck = true,
                 jbod = false, services = true, cron = true,
                 packages = true },
  },
  -- Safe Mode (operator request, Jul 2026). The recovery boot: NOTHING
  -- third-party or optional runs — no rc.d services, no cron jobs, no
  -- package commands, no net, no themes — but the full shell and the pkg
  -- ADMIN verbs still work, so a broken add-on/service/theme can be
  -- removed and the box rebooted back to normal. Distinct from `minimal`
  -- in intent: minimal is "small on purpose" (a tight box's everyday
  -- profile); safe is "trust nothing until I fix it" and boots loud
  -- (text verbosity + a SAFE MODE banner), never quiet.
  safe = {
    description = "Safe Mode — kernel + shell only; no services/packages/net",
    verbosity = "text",
    features = { swap = false, power = false, net = false, theme = false,
                 compat = false, audio = false, integrityCheck = false,
                 jbod = false, services = false, cron = false,
                 packages = false },
  },
}
bootcfg.PROFILES = PROFILES

-- Stable display order for UIs (pairs() order is unspecified).
bootcfg.PROFILE_ORDER = { "minimal", "normal", "full", "diagnostic", "safe" }

-- Muter levels, least → most chatter. silent: nothing; splash: logo + bar;
-- text: per-stage lines; verbose: text + timings + the hardware table.
local VERBOSITY = { "silent", "splash", "text", "verbose" }
local VERBOSITY_RANK = { silent = 0, splash = 1, text = 2, verbose = 3 }
bootcfg.VERBOSITY = VERBOSITY

-- Boot-log echo threshold per verbosity: which kernel.log LEVELS reach the
-- screen during boot (kernel.log numbering: DEBUG=0, INFO=1, WARN=2, ERROR=3,
-- FATAL=4). This is the SINGLE source of truth for the muter, consumed by the
-- bootloader. silent=4 → effectively nothing (only a FATAL would show);
-- splash=2 → hide the per-stage INFO chatter (the loading bar narrates it) but
-- keep WARN+; text=1 → INFO+; verbose=0 → everything (DEBUG+).
local ECHO_MINLEVEL = { silent = 4, splash = 2, text = 1, verbose = 0 }
function bootcfg.echoMinLevel(verbosity)
  return ECHO_MINLEVEL[verbosity] or 1   -- unknown → text-equivalent
end

local DEFAULTS = {
  profile    = "normal",
  verbosity  = nil,        -- nil = use the profile's default
  showConfig = true,       -- show the System Configuration POST screen briefly
  advanced   = {},         -- per-feature overrides; values are true/false
  cpuTier    = nil,        -- operator CPU-tier override (consumed by sysinfo)
  dataTier   = nil,        -- operator Data Card-tier override (consumed by sysinfo)
  -- Operator knobs (Jul 2026):
  ui         = nil,        -- nil/"panels" = the TUI; "cli" = boot straight to
                           -- the minimal CLI shell (system-wide, all seats)
  repair     = false,      -- ONE-SHOT: run self-repair on the next boot, then
                           -- the flag clears itself (kernel.repair)
  ramGate    = nil,        -- memory declaration for the optional-stage gates:
                           -- nil = measure free RAM (auto); true = "plenty"
                           -- (force gates open); false = "tight" (force shut).
                           -- This is the "tell TOS what it has" knob for the
                           -- one resource whose HEADROOM (not size) drives
                           -- boot decisions. Reliably-detectable hardware
                           -- (GPU, screen, modem) deliberately has no
                           -- override — TOS trusts what it can see.
}

-- ============================================================
-- Load + normalize
-- ============================================================

local function normalize(cfg)
  if type(cfg) ~= "table" then cfg = {} end
  -- profile
  if not PROFILES[cfg.profile] then cfg.profile = "normal" end
  -- verbosity: keep only a known level; nil falls back to the profile default.
  if cfg.verbosity ~= nil and not VERBOSITY_RANK[cfg.verbosity] then
    cfg.verbosity = nil
  end
  -- showConfig: boolean, default true
  if cfg.showConfig == nil then cfg.showConfig = true end
  cfg.showConfig = cfg.showConfig and true or false
  -- advanced: keep only known features with boolean values
  local adv = {}
  if type(cfg.advanced) == "table" then
    for _, name in ipairs(FEATURES) do
      local v = cfg.advanced[name]
      if type(v) == "boolean" then adv[name] = v end
    end
  end
  cfg.advanced = adv
  -- cpuTier: 1..3 or nil
  local t = tonumber(cfg.cpuTier)
  cfg.cpuTier = (t and t >= 1 and t <= 3) and math.floor(t) or nil
  -- dataTier: 1..3 or nil
  local dt = tonumber(cfg.dataTier)
  cfg.dataTier = (dt and dt >= 1 and dt <= 3) and math.floor(dt) or nil
  -- ui: only the known shapes; "home" (the merged surface) is the default
  -- and collapses to nil so a default-shaped boot.cfg stays empty.
  if cfg.ui ~= "cli" and cfg.ui ~= "split" then cfg.ui = nil end
  -- repair: boolean one-shot, default off
  cfg.repair = cfg.repair == true
  -- ramGate: strict tri-state (nil/true/false); anything else → auto
  if type(cfg.ramGate) ~= "boolean" then cfg.ramGate = nil end
  return cfg
end
bootcfg._normalize = normalize

--- Load /etc/boot.cfg, fail-safe. Never raises; an unreadable/corrupt file
--- yields the `normal` defaults so boot always proceeds.
--- @param fs table  anything with exists(path) + readFile(path)
function bootcfg.load(fs)
  local cfg = {
    profile = DEFAULTS.profile, verbosity = DEFAULTS.verbosity,
    showConfig = DEFAULTS.showConfig, advanced = {}, cpuTier = DEFAULTS.cpuTier,
    dataTier = DEFAULTS.dataTier,
    ui = DEFAULTS.ui, repair = DEFAULTS.repair, ramGate = DEFAULTS.ramGate,
  }
  if fs and fs.exists and fs.exists(PATH) then
    local ok, data = pcall(fs.readFile, PATH)
    if ok and type(data) == "string" and #data > 0 and #data <= MAX_BYTES then
      -- boot.cfg is a serialized data table (`return { ... }`), parsed by the
      -- safe recursive-descent decoder — never load()'d as code.
      local okS, serialize = pcall(require, "kernel.serialize")
      if okS and serialize and serialize.decode then
        local parsed = serialize.decode(data, { maxBytes = MAX_BYTES })
        if type(parsed) == "table" then
          for k, v in pairs(parsed) do cfg[k] = v end
        end
      end
    end
  end
  return normalize(cfg)
end

--- Persist a (normalized) config back to /etc/boot.cfg.
--- @param fs table  anything with writeFile/writeFileAtomic
function bootcfg.save(fs, cfg)
  cfg = normalize(cfg)
  local okS, serialize = pcall(require, "kernel.serialize")
  if not (okS and serialize and serialize.encode) then
    return false, "serialize unavailable"
  end
  local data = serialize.encode({
    profile = cfg.profile, verbosity = cfg.verbosity,
    showConfig = cfg.showConfig, advanced = cfg.advanced,
    cpuTier = cfg.cpuTier, dataTier = cfg.dataTier,
    ui = cfg.ui, repair = cfg.repair or nil, ramGate = cfg.ramGate,
  })
  local writer = fs.writeFileAtomic or fs.writeFile
  return writer(PATH, data)
end

-- ============================================================
-- Resolution helpers (consumed by the stage driver, step #4)
-- ============================================================

--- Effective muter level for this config (explicit override, else profile).
function bootcfg.verbosity(cfg)
  cfg = cfg or {}
  return cfg.verbosity or (PROFILES[cfg.profile] or PROFILES.normal).verbosity
end

--- True if `level` should be shown at the config's verbosity. e.g.
--- bootcfg.shows(cfg, "text") is false on a silent/splash boot.
function bootcfg.shows(cfg, level)
  return (VERBOSITY_RANK[bootcfg.verbosity(cfg)] or 2) >= (VERBOSITY_RANK[level] or 0)
end

--- Should optional feature `name` load? Resolution order:
---   1. an explicit advanced override (true/false),
---   2. the profile's pin for that feature,
---   3. the RAM gate (`ramOK`, default true) — today's behavior.
function bootcfg.wants(cfg, name, ramOK)
  cfg = cfg or {}
  local adv = cfg.advanced and cfg.advanced[name]
  if type(adv) == "boolean" then return adv end
  local pf = (PROFILES[cfg.profile] or PROFILES.normal).features
  if type(pf[name]) == "boolean" then return pf[name] end
  return ramOK ~= false
end

--- Resolve the RAM gate: the operator's declaration wins, else the live
--- measurement. `detected` is the caller's "free RAM looks fine" boolean.
function bootcfg.ramOK(cfg, detected)
  if cfg and type(cfg.ramGate) == "boolean" then return cfg.ramGate end
  return detected ~= false
end

--- Effective startup interface: "home" (default), "split" or "cli".
---
--- "home" is the merged surface — one tab, tiles and files as two views
--- of it, the prompt resident in both. "split" is the pre-merge shape,
--- kept for operators who want the Desktop as its own tab. Both are the
--- panels TUI; only "cli" is a different program.
function bootcfg.ui(cfg)
  local v = cfg and cfg.ui
  if v == "cli" or v == "split" then return v end
  return "home"
end

bootcfg.PATH = PATH

return bootcfg
