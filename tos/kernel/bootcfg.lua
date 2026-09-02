local bootcfg = {}

local PATH = "/etc/boot.cfg"
local MAX_BYTES = 8192

local FEATURES = {
  "swap", "power", "net", "theme", "compat", "audio", "integrityCheck",

  "jbod",

  "services", "cron", "packages",
}
bootcfg.FEATURES = FEATURES

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

    features = { jbod = false },
  },
  full = {
    description = "Load every available subsystem (RAM permitting)",
    verbosity = "text",

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

bootcfg.PROFILE_ORDER = { "minimal", "normal", "full", "diagnostic", "safe" }

local VERBOSITY = { "silent", "splash", "text", "verbose" }
local VERBOSITY_RANK = { silent = 0, splash = 1, text = 2, verbose = 3 }
bootcfg.VERBOSITY = VERBOSITY

local ECHO_MINLEVEL = { silent = 4, splash = 2, text = 1, verbose = 0 }
function bootcfg.echoMinLevel(verbosity)
  return ECHO_MINLEVEL[verbosity] or 1
end

local DEFAULTS = {
  profile    = "normal",
  verbosity  = nil,
  showConfig = true,
  advanced   = {},
  cpuTier    = nil,
  dataTier   = nil,

  ui         = nil,

  repair     = false,

  ramGate    = nil,

}

local function normalize(cfg)
  if type(cfg) ~= "table" then cfg = {} end

  if not PROFILES[cfg.profile] then cfg.profile = "normal" end

  if cfg.verbosity ~= nil and not VERBOSITY_RANK[cfg.verbosity] then
    cfg.verbosity = nil
  end

  if cfg.showConfig == nil then cfg.showConfig = true end
  cfg.showConfig = cfg.showConfig and true or false

  local adv = {}
  if type(cfg.advanced) == "table" then
    for _, name in ipairs(FEATURES) do
      local v = cfg.advanced[name]
      if type(v) == "boolean" then adv[name] = v end
    end
  end
  cfg.advanced = adv

  local t = tonumber(cfg.cpuTier)
  cfg.cpuTier = (t and t >= 1 and t <= 3) and math.floor(t) or nil

  local dt = tonumber(cfg.dataTier)
  cfg.dataTier = (dt and dt >= 1 and dt <= 3) and math.floor(dt) or nil

  if cfg.ui ~= "cli" and cfg.ui ~= "split" then cfg.ui = nil end

  cfg.repair = cfg.repair == true

  if type(cfg.ramGate) ~= "boolean" then cfg.ramGate = nil end
  return cfg
end
bootcfg._normalize = normalize

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

function bootcfg.verbosity(cfg)
  cfg = cfg or {}
  return cfg.verbosity or (PROFILES[cfg.profile] or PROFILES.normal).verbosity
end

function bootcfg.shows(cfg, level)
  return (VERBOSITY_RANK[bootcfg.verbosity(cfg)] or 2) >= (VERBOSITY_RANK[level] or 0)
end

function bootcfg.wants(cfg, name, ramOK)
  cfg = cfg or {}
  local adv = cfg.advanced and cfg.advanced[name]
  if type(adv) == "boolean" then return adv end
  local pf = (PROFILES[cfg.profile] or PROFILES.normal).features
  if type(pf[name]) == "boolean" then return pf[name] end
  return ramOK ~= false
end

function bootcfg.ramOK(cfg, detected)
  if cfg and type(cfg.ramGate) == "boolean" then return cfg.ramGate end
  return detected ~= false
end

function bootcfg.ui(cfg)
  local v = cfg and cfg.ui
  if v == "cli" or v == "split" then return v end
  return "home"
end

bootcfg.PATH = PATH

return bootcfg
