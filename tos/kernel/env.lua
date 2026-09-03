-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Environment Variables  ║
-- ╚══════════════════════════════════════╝
-- Per-process key-value environment, inherited on spawn.

local env = {}

-- System-wide defaults (inherited by all processes if not overridden)
local defaults = {
  PATH     = "/usr/bin:/bin:/tos/shell",
  HOME     = "/",
  SHELL    = "/tos/shell/init.lua",
  TERM     = "tos",
  TOS_VERSION = _G._TOS and _G._TOS.version or "1.4.0",
}

--- Get the env table for the current process, or system defaults.
-- @param proc table|nil: Process object (from proc.current())
-- @return table: The environment table (mutable reference)
function env.get(process)
  if process and process.env then return process.env end
  return defaults
end

--- Read a single variable from process env, falling back to defaults.
function env.read(process, key)
  if process and process.env and process.env[key] ~= nil then
    return process.env[key]
  end
  return defaults[key]
end

--- Write a variable into a process env.
function env.write(process, key, value)
  if not process then return false end
  if not process.env then process.env = {} end
  process.env[key] = value
  return true
end

--- Create a child env table inheriting from a parent process env.
-- Performs a shallow copy so child modifications don't affect parent.
function env.inherit(parentProcess)
  local child = {}
  -- Start with system defaults
  for k, v in pairs(defaults) do child[k] = v end
  -- Overlay parent values
  if parentProcess and parentProcess.env then
    for k, v in pairs(parentProcess.env) do child[k] = v end
  end
  return child
end

--- Set a system-wide default.
-- #SEC C8: mutating the system-wide PATH (or any default) used to be
-- callable from any sandboxed program via shell.setPath -> env.setDefault.
-- Now requires an ADMIN+ session; un-sessioned callers (kernel boot
-- before users.init runs) are still allowed so defaults can be seeded.
function env.setDefault(key, value)
  local ok, usersmod = pcall(require, "kernel.users")
  if ok and usersmod and usersmod.currentSession then
    local sess = usersmod.currentSession()
    if sess and not sess.isKernel and sess.tier < (usersmod.TIER and usersmod.TIER.ADMIN or 2) then
      return false, "env.setDefault requires admin tier"
    end
  end
  defaults[key] = value
  return true
end

--- List all env vars for a process (merged with defaults).
function env.list(process)
  local result = {}
  -- #SEC M18: return a copy, not the live `defaults` table. Returning
  -- the live reference let any caller mutate the system-wide defaults.
  for k, v in pairs(defaults) do result[k] = v end
  if process and process.env then
    for k, v in pairs(process.env) do result[k] = v end
  end
  return result
end

return env
