-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - System Configuration   ║
-- ║  Device profiles & system settings   ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")
local serialize = require("kernel.serialize")

local config = {}

-- Default configuration
local CONFIG_PATH = "/etc/tos.cfg"
local defaults = {
  -- Device profile
  device       = "computer",   -- "computer", "tablet", or "server"
  hostname     = "tos",        -- Network hostname

  -- Display
  compactUI    = false,        -- Use compact layout (auto for small screens)
  refreshRate  = 10,           -- TUI refresh target (ticks/sec)

  -- Power (tablet only)
  powerSave    = false,        -- Reduce refresh rate when on battery
  lowBatWarn   = 15,           -- Warn at this battery %
  critBatWarn  = 5,            -- Critical warning at this %
  showBattery  = false,        -- Show battery in status bar

  -- Security
  autoLockout  = true,         -- Lock accounts after failed logins
  maxAttempts  = 5,            -- Failed attempts before lockout
  sessionTimeout = 0,          -- Auto-logout after N seconds idle (0=never)
  guestAccess  = false,        -- Allow guest login without password

  -- Network
  encryptComms = true,         -- Encrypt network messages when possible
  listenPort   = 42,           -- Default modem port
  broadcastPort = 43,          -- Discovery broadcast port

  -- Server profile (server blades in OC racks)
  headless     = false,        -- Boot without display; auto-set for GPU-less servers
  rackSlot     = 0,            -- Which slot (1-4) in the rack; 0 = auto-detect / N/A
  autoServices = true,         -- Auto-start /etc/rc.d/ services on headless boot

  -- Misc
  verbose      = false,        -- Verbose boot logging
  timezone     = 0,            -- Offset from server time (cosmetic)
}

-- Active config (merged defaults + saved)
local active = {}

-- ============================================================
-- Init / Load / Save
-- ============================================================

function config.init(fsModule)
  config._fs = fsModule

  -- Start with defaults
  for k, v in pairs(defaults) do
    active[k] = v
  end

  -- Load saved config if exists
  if fsModule.exists(CONFIG_PATH) then
    local data, err = fsModule.readFile(CONFIG_PATH)
    if data then
      local saved = serialize.decode(data)
      if saved then
        for k, v in pairs(saved) do
          active[k] = v
        end
      end
    end
  end

  -- ── Hardware-based profile detection ──────────────────
  -- Always check hardware — don't trust saved config for device type,
  -- since the same disk could be moved between a tablet, computer, and
  -- a server rack.
  local component2 = require("component")

  local function detectProfile()
    -- Tablet: OC tablets expose a "tablet" component.
    local tabAddr = component2.list("tablet")()
    if tabAddr then return "tablet" end

    -- Server blade detection. OC server blades typically:
    --   • Have NO gpu and NO screen (headless by default)
    --   • May have a modem (network card in the rack backplane)
    --   • May list zero keyboards
    -- A computer case could also have no GPU if the user removed it,
    -- but the combination of no-GPU + no-screen + no-keyboard is the
    -- best heuristic for "this is a rack blade, not a desktop".
    local hasGPU      = component2.list("gpu")() ~= nil
    local hasScreen   = component2.list("screen")() ~= nil
    local hasKeyboard = component2.list("keyboard")() ~= nil

    if not hasGPU and not hasScreen and not hasKeyboard then
      return "server"
    end

    -- Fallback: ordinary desktop computer.
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
  -- "computer" keeps defaults as-is.

  return true
end

function config.save()
  if not config._fs then return false, "FS not initialized" end
  local data = serialize.encode(active)
  return config._fs.writeFile(CONFIG_PATH, data)
end

-- ============================================================
-- Accessors
-- ============================================================

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

--- Check if running in tablet mode
function config.isTablet()
  return active.device == "tablet"
end

--- Check if running as a server blade (rack-mounted, typically headless)
function config.isServer()
  return active.device == "server"
end

--- Check if the system is headless (no GPU/screen). True for server
--- blades by default, but can also be forced via config for computers
--- that act as dedicated service hosts.
function config.isHeadless()
  return active.headless == true
end

--- Get the device profile name
function config.deviceType()
  return active.device or "computer"
end

--- Reset a key to default
function config.reset(key)
  active[key] = defaults[key]
end

--- Reset all to defaults
function config.resetAll()
  for k, v in pairs(defaults) do
    active[k] = v
  end
end

-- Export defaults for reference
config.DEFAULTS = defaults

return config
