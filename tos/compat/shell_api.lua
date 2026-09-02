local function fs()
  return (_G._TOS and _G._TOS.securefs) or require("kernel.securefs")
end
local env = require("kernel.env")

local shell = {}

local workingDir = "/"

local aliases = {}

local function getPathDirs(process)
  local path = env.read(process, "PATH") or "/usr/bin:/bin"
  local dirs = {}
  for dir in path:gmatch("[^:]+") do
    dirs[#dirs + 1] = dir
  end
  return dirs
end

function shell.getWorkingDirectory()
  return workingDir
end

function shell.setWorkingDirectory(dir)
  workingDir = fs().normalize(dir)
end

function shell.resolve(name, ext, _depth)
  if not name then return nil end
  _depth = _depth or 0
  local f = fs()

  if name:sub(1, 1) == "/" then
    if f.exists(name) then return name end
    if ext and f.exists(name .. ext) then return name .. ext end
    return nil
  end

  if aliases[name] and _depth < 8 then
    return shell.resolve(aliases[name], ext, _depth + 1)
  end

  local cwd = f.join(workingDir, name)
  if f.exists(cwd) then return cwd end
  if ext and f.exists(cwd .. ext) then return cwd .. ext end

  for _, dir in ipairs(getPathDirs()) do
    local full = f.join(dir, name)
    if f.exists(full) then return full end
    if ext and f.exists(full .. ext) then return full .. ext end
  end

  return nil
end

function shell.execute(command, ...)
  local path = shell.resolve(command, ".lua")
  if not path then
    return false, "Program not found: " .. command
  end

  local resolvedViaPath = (command:sub(1, 1) ~= "/")
  if resolvedViaPath then
    local UNSAFE_PREFIXES = { "/mnt/", "/tmp/", "/public/", "/home/" }
    for _, p in ipairs(UNSAFE_PREFIXES) do
      if path:sub(1, #p) == p then
        return false, "Refusing to PATH-resolve to user-writable location: " .. path
      end
    end
  end

  local source = fs().readFile(path)
  if not source then
    return false, "Cannot read: " .. path
  end

  local session  = nil
  local parentCaps = nil
  local okU, usersmod = pcall(require, "kernel.users")
  if okU and usersmod and usersmod.currentSession then
    session = usersmod.currentSession()
  end
  local okP, procMod = pcall(require, "kernel.process")
  if okP and procMod and procMod.current then
    local cur = procMod.current()
    if cur and cur.caps then parentCaps = cur.caps end
  end

  local okS, sandbox = pcall(require, "kernel.sandbox")
  if not okS or not sandbox then
    return false, "Sandbox unavailable"
  end

  local caps = parentCaps or {
    ["fs.read"]   = true,
    ["compat.io"] = true,
  }

  local env = sandbox.build{
    session = session,
    caps    = caps,
  }

  local fn, err = load(source, "=" .. path, "t", env)
  if not fn then
    return false, "Compile error: " .. tostring(err)
  end
  return pcall(fn, ...)
end

function shell.parse(...)
  local params = table.pack(...)
  local args = {}
  local options = {}
  for i = 1, params.n do
    local p = tostring(params[i])
    if p:sub(1, 2) == "--" then
      local key, val = p:match("^%-%-([%w_%-]+)=?(.*)")
      if key then
        options[key] = val ~= "" and val or true
      end
    elseif p:sub(1, 1) == "-" then
      for j = 2, #p do
        options[p:sub(j, j)] = true
      end
    else
      args[#args + 1] = p
    end
  end
  return args, options
end

function shell.getAlias(name)
  return aliases[name]
end

function shell.setAlias(name, value)
  aliases[name] = value
end

function shell.aliases()
  local result = {}
  for k, v in pairs(aliases) do result[k] = v end
  return result
end

function shell.getPath()
  return env.read(nil, "PATH") or "/usr/bin:/bin"
end

function shell.setPath(path)
  env.setDefault("PATH", path)
end

return shell
