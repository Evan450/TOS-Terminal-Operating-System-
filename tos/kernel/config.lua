local computer = require("computer")
local serialize = require("kernel.serialize")

local config = {}

local CONFIG_PATH = "/etc/tos.cfg"
local defaults = {

  device       = "computer",
  hostname     = "tos",

  compactUI    = false,
  refreshRate  = 10,

  screenRes         = "auto",
  screenColsPerBlock = 10,
  screenRowsPerBlock = 4,

  powerSave    = false,
  lowBatWarn   = 15,
  critBatWarn  = 5,
  showBattery  = false,

  autoLockout  = true,
  maxAttempts  = 5,
  sessionTimeout = 0,
  guestAccess  = false,

  encryptComms = true,
  listenPort   = 42,

  internet        = true,
  internetMaxKB   = 64,
  internetTimeout = 15,

  headless     = false,
  rackSlot     = 0,
  autoServices = true,

  verbose      = false,
  timezone     = 0,
}

local active = {}

function config.init(fsModule)
  config._fs = fsModule

  for k, v in pairs(defaults) do
    active[k] = v
  end

  local saved = serialize.loadFile(fsModule, CONFIG_PATH)
  if saved then
    for k, v in pairs(saved) do
      active[k] = v
    end
  end

  local component2 = require("component")

  local function detectProfile()

    local tabAddr = component2.list("tablet")()
    if tabAddr then return "tablet" end

    local hasGPU      = component2.list("gpu")() ~= nil
    local hasScreen   = component2.list("screen")() ~= nil
    local hasKeyboard = component2.list("keyboard")() ~= nil

    if not hasGPU and not hasScreen and not hasKeyboard then
      return "server"
    end

    return "computer"
  end

  local profile = detectProfile()
  active.device = profile

  if profile == "tablet" then
    active.showBattery = true
    active.powerSave   = true
  elseif profile == "server" then
    active.headless = true
  end

  return true
end

function config.save()
  return serialize.saveFile(config._fs, CONFIG_PATH, active)
end

function config.get(key)
  if active[key] ~= nil then return active[key] end
  return defaults[key]
end

function config.set(key, value)
  active[key] = value
end

function config.getAll()
  local result = {}
  for k, v in pairs(active) do
    result[k] = v
  end
  return result
end

function config.isTablet()
  return active.device == "tablet"
end

function config.isHeadless()
  return active.headless == true
end

function config.deviceType()
  return active.device or "computer"
end

function config.reset(key)
  active[key] = defaults[key]
end

config.DEFAULTS = defaults

return config
