-- TOS OpenOS Compatibility - shell API
-- Provides the OpenOS shell interface for program resolution and execution.
-- OpenOS programs use require("shell") for path resolution and program execution.

-- Deferred filesystem accessor. Resolves to securefs (permission-checked)
-- so shell.resolve / shell.execute honor the caller's ACLs.
local function fs()
  return (_G._TOS and _G._TOS.securefs) or require("kernel.securefs")
end
local env = require("kernel.env")

local shell = {}

-- Working directory (per-session, set by TOS shell)
local workingDir = "/"

-- Aliases: short name -> full path
local aliases = {}

-- PATH directories (colon-separated, from env)
local function getPathDirs(process)
  local path = env.read(process, "PATH") or "/usr/bin:/bin"
  local dirs = {}
  for dir in path:gmatch("[^:]+") do
    dirs[#dirs + 1] = dir
  end
  return dirs
end

--- Get current working directory.
function shell.getWorkingDirectory()
  return workingDir
end

--- Set current working directory.
function shell.setWorkingDirectory(dir)
  workingDir = fs().normalize(dir)
end

--- Resolve a program name to a full path.
-- Searches working directory, then PATH directories.
function shell.resolve(name, ext, _depth)
  if not name then return nil end
  _depth = _depth or 0
  local f = fs()
  -- If already absolute and exists, return it
  if name:sub(1, 1) == "/" then
    if f.exists(name) then return name end
    if ext and f.exists(name .. ext) then return name .. ext end
    return nil
  end

  -- Check aliases (with recursion limit to prevent infinite loops)
  if aliases[name] and _depth < 8 then
    return shell.resolve(aliases[name], ext, _depth + 1)
  end

  -- Check working directory
  local cwd = f.join(workingDir, name)
  if f.exists(cwd) then return cwd end
  if ext and f.exists(cwd .. ext) then return cwd .. ext end

  -- Check PATH
  for _, dir in ipairs(getPathDirs()) do
    local full = f.join(dir, name)
    if f.exists(full) then return full end
    if ext and f.exists(full .. ext) then return full .. ext end
  end

  return nil
end

--- Execute a program by name.
function shell.execute(command, ...)
  local path = shell.resolve(command, ".lua")
  if not path then
    return false, "Program not found: " .. command
  end
  local source = fs().readFile(path)
  if not source then
    return false, "Cannot read: " .. path
  end
  local fn, err = load(source, "=" .. path, "t", _ENV)
  if not fn then
    return false, "Compile error: " .. tostring(err)
  end
  return pcall(fn, ...)
end

--- Parse a command line into program name and arguments.
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

--- Get/set aliases.
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

--- Get PATH directories.
function shell.getPath()
  return env.read(nil, "PATH") or "/usr/bin:/bin"
end

function shell.setPath(path)
  env.setDefault("PATH", path)
end

return shell
