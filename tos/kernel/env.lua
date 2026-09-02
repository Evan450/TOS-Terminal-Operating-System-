local env = {}

local defaults = {
  PATH     = "/usr/bin:/bin:/tos/shell",
  HOME     = "/",
  SHELL    = "/tos/shell/init.lua",
  TERM     = "tos",
  TOS_VERSION = _G._TOS and _G._TOS.version or "1.4.0",
}

function env.get(process)
  if process and process.env then return process.env end
  return defaults
end

function env.read(process, key)
  if process and process.env and process.env[key] ~= nil then
    return process.env[key]
  end
  return defaults[key]
end

function env.write(process, key, value)
  if not process then return false end
  if not process.env then process.env = {} end
  process.env[key] = value
  return true
end

function env.inherit(parentProcess)
  local child = {}

  for k, v in pairs(defaults) do child[k] = v end

  if parentProcess and parentProcess.env then
    for k, v in pairs(parentProcess.env) do child[k] = v end
  end
  return child
end

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

function env.list(process)
  local result = {}

  for k, v in pairs(defaults) do result[k] = v end
  if process and process.env then
    for k, v in pairs(process.env) do result[k] = v end
  end
  return result
end

return env
