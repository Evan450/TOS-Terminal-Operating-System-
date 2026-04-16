-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Module Manager        ║
-- ║  Install / enable / disable modules ║
-- ╚══════════════════════════════════════╝
-- Manages optional user-installable modules.
-- Modules live under /usr/modules/<name>/ and are described
-- by a module.cfg manifest (serialized Lua table).
--
-- Module types:
--   command  — registers shell commands
--   service  — has start/stop lifecycle (like rc.d services)
--   library  — provides a require()-able name
--
-- Module entry file returns a table:
--   { commands = { name = fn(args, o) }, start = fn, stop = fn }

local modules = {}

local MODULES_DIR    = "/usr/modules"
local REGISTRY_PATH  = "/usr/modules/registry.dat"

-- Dependencies (set during init)
local fs   = nil
local log  = nil
local event = nil

-- State
local registry = {}   -- name -> manifest + { enabled, installedAt }
local active   = {}   -- name -> loaded module table (only for enabled modules)

-- ============================================================
-- Initialization
-- ============================================================

function modules.init(deps)
  fs    = deps.fs
  log   = deps.log
  event = deps.event

  -- Ensure module directory exists
  if not fs.exists(MODULES_DIR) then
    fs.makeDirectory(MODULES_DIR)
  end

  modules.loadRegistry()

  -- Auto-scan for module dirs that aren't in the registry
  -- (handles manually copied modules or lost registry)
  modules.scan()

  return true
end

-- ============================================================
-- Registry persistence
-- ============================================================

function modules.loadRegistry()
  registry = {}
  if not fs.exists(REGISTRY_PATH) then return end

  local content = fs.readFile(REGISTRY_PATH)
  if not content then return end

  local serialize = require("kernel.serialize")
  local data, err = serialize.decode(content)
  if data and type(data) == "table" then
    registry = data
  elseif log then
    log.warn("modules", "Registry decode error: " .. tostring(err))
  end
end

function modules.saveRegistry()
  local serialize = require("kernel.serialize")
  fs.writeFile(REGISTRY_PATH, serialize.encode(registry))
end

-- ============================================================
-- Manifest parsing
-- ============================================================

local REQUIRED_FIELDS = { "name", "version", "type", "files" }
local VALID_TYPES = { command = true, service = true, library = true }

--- Read and validate a module.cfg from a directory.
-- @param dir string: Directory containing module.cfg
-- @return table|nil, string|nil: Parsed manifest or nil + error
function modules.readManifest(dir)
  local path = fs.join(dir, "module.cfg")
  if not fs.exists(path) then
    return nil, "No module.cfg found"
  end

  local content = fs.readFile(path)
  if not content then
    return nil, "Cannot read module.cfg"
  end

  local serialize = require("kernel.serialize")
  local manifest, err = serialize.decode(content)
  if not manifest then
    return nil, "Invalid module.cfg: " .. tostring(err)
  end

  -- Validate required fields
  for _, field in ipairs(REQUIRED_FIELDS) do
    if not manifest[field] then
      return nil, "Missing required field: " .. field
    end
  end

  if not VALID_TYPES[manifest.type] then
    return nil, "Invalid type: " .. tostring(manifest.type) .. " (expected command/service/library)"
  end

  -- Validate name (alphanumeric + dashes)
  if not manifest.name:match("^[%w%-]+$") then
    return nil, "Invalid name: use only letters, numbers, dashes"
  end

  -- files must be a non-empty array
  if type(manifest.files) ~= "table" or #manifest.files == 0 then
    return nil, "files must be a non-empty list"
  end

  return manifest
end

-- ============================================================
-- Install / Uninstall
-- ============================================================

--- Install a module from a source directory.
-- Copies module.cfg + listed files into /usr/modules/<name>/.
-- @param srcDir string: Directory containing module.cfg and files
-- @return boolean, string: success, or false + error
function modules.install(srcDir)
  local manifest, err = modules.readManifest(srcDir)
  if not manifest then
    return false, err
  end

  local name = manifest.name
  local destDir = fs.join(MODULES_DIR, name)

  -- If already installed, disable first
  if registry[name] and active[name] then
    modules.disable(name)
  end

  -- Create destination directory
  if not fs.exists(destDir) then
    fs.makeDirectory(destDir)
  end

  -- Copy module.cfg
  local cfgContent = fs.readFile(fs.join(srcDir, "module.cfg"))
  if cfgContent then
    fs.writeFile(fs.join(destDir, "module.cfg"), cfgContent)
  end

  -- Copy listed files
  local copied, failed = 0, 0
  for _, file in ipairs(manifest.files) do
    local srcPath = fs.join(srcDir, file)
    local dstPath = fs.normalize(fs.join(destDir, file))

    -- Prevent directory traversal: ensure destination is under destDir
    if not (dstPath == destDir or dstPath:sub(1, #destDir + 1) == destDir .. "/") then
      if log then log.warn("modules", "Skipping file with path traversal: " .. file) end
      failed = failed + 1
    else
      -- Create subdirectories if needed
      local dir = fs.split(dstPath)
      if dir and dir ~= "/" and not fs.exists(dir) then
        fs.makeDirectory(dir)
      end

      local data = fs.readFile(srcPath)
      if data then
        if fs.writeFile(dstPath, data) then
          copied = copied + 1
        else
          failed = failed + 1
        end
      else
        failed = failed + 1
      end
    end
  end

  if failed > 0 then
    return false, string.format("Copied %d files, %d failed", copied, failed)
  end

  -- Register in registry
  registry[name] = {
    name        = manifest.name,
    version     = manifest.version,
    description = manifest.description or "",
    author      = manifest.author or "",
    type        = manifest.type,
    commands    = manifest.commands or {},
    provides    = manifest.provides,
    files       = manifest.files,
    enabled     = false,
    installedAt = os.time and os.time() or 0,
  }
  modules.saveRegistry()

  if log then
    log.info("modules", "Installed: " .. name .. " v" .. manifest.version)
  end

  return true, copied .. " files"
end

--- Recursively remove a directory and all its contents.
local function removeRecursive(path)
  if fs.isDirectory(path) then
    for name in fs.list(path) do
      removeRecursive(fs.join(path, name))
    end
  end
  fs.remove(path)
end

--- Uninstall a module by name.
-- @return boolean, string
function modules.uninstall(name)
  if not registry[name] then
    return false, "Module not installed: " .. name
  end

  -- Disable if active
  if active[name] then
    modules.disable(name)
  end

  -- Remove module directory recursively (handles nested subdirectories)
  local modDir = fs.join(MODULES_DIR, name)
  if fs.exists(modDir) then
    removeRecursive(modDir)
  end

  -- Remove from registry
  local ver = registry[name].version
  registry[name] = nil
  modules.saveRegistry()

  if log then
    log.info("modules", "Uninstalled: " .. name .. " v" .. ver)
  end

  return true
end

-- ============================================================
-- Enable / Disable
-- ============================================================

--- Load and activate a module.
-- @return boolean, string
function modules.enable(name)
  local entry = registry[name]
  if not entry then
    return false, "Module not installed: " .. name
  end
  if active[name] then
    return true, "Already enabled"
  end

  local modDir = fs.join(MODULES_DIR, name)

  -- Determine entry file: init.lua if it exists, otherwise first file
  local entryFile = fs.join(modDir, "init.lua")
  if not fs.exists(entryFile) then
    entryFile = fs.join(modDir, entry.files[1])
  end

  if not fs.exists(entryFile) then
    return false, "Entry file not found"
  end

  local source = fs.readFile(entryFile)
  if not source then
    return false, "Cannot read entry file"
  end

  -- Modules get standard globals + require, but not modules.lua internals.
  -- Shared libraries are shallow-copied to prevent host poisoning.
  local function copyLib(lib)
    if not lib then return nil end
    local c = {}
    for k, v in pairs(lib) do c[k] = v end
    return c
  end
  local _computer = rawget(_G, "computer") or require("computer")
  local _component = rawget(_G, "component") or require("component")
  local modEnv = {
    assert = assert, error = error, pcall = pcall, xpcall = xpcall,
    type = type, tostring = tostring, tonumber = tonumber,
    pairs = pairs, ipairs = ipairs, next = next, select = select,
    rawget = rawget, rawset = rawset, rawlen = rawlen, rawequal = rawequal,
    setmetatable = setmetatable, getmetatable = getmetatable,
    require = require, load = load, print = print,
    math = copyLib(math), string = copyLib(string), table = copyLib(table),
    os = copyLib(os),
    computer = _computer, component = _component,
    coroutine = copyLib(coroutine), utf8 = utf8,
  }
  modEnv._G = modEnv

  local fn, loadErr = load(source, "=" .. name, "t", modEnv)
  if not fn then
    return false, "Load error: " .. tostring(loadErr)
  end

  local ok, result = pcall(fn)
  if not ok then
    return false, "Runtime error: " .. tostring(result)
  end

  -- Store the loaded module table
  if type(result) == "table" then
    active[name] = result

    -- Start services
    if entry.type == "service" and result.start then
      local sok, serr = pcall(result.start)
      if not sok and log then
        log.warn("modules", "Service start failed for " .. name .. ": " .. tostring(serr))
      end
    end
  else
    active[name] = {}
  end

  entry.enabled = true
  modules.saveRegistry()

  if log then
    log.info("modules", "Enabled: " .. name)
  end

  return true
end

--- Disable and unload a module.
-- @return boolean, string
function modules.disable(name)
  local entry = registry[name]
  if not entry then
    return false, "Module not installed: " .. name
  end

  local mod = active[name]
  if mod then
    -- Stop services
    if entry.type == "service" and mod.stop then
      pcall(mod.stop)
    end

    -- Clean up event listeners registered by this module
    if event and event.removeSource then
      event.removeSource("mod:" .. name)
    end

    active[name] = nil
  end

  entry.enabled = false
  modules.saveRegistry()

  if log then
    log.info("modules", "Disabled: " .. name)
  end

  return true
end

--- Start all modules that were marked enabled in the registry.
function modules.startAll()
  for name, entry in pairs(registry) do
    if entry.enabled then
      local ok, err = modules.enable(name)
      if not ok and log then
        log.warn("modules", "Failed to start " .. name .. ": " .. tostring(err))
      end
    end
  end
end

--- Stop all active modules.
function modules.stopAll()
  -- Collect names first to avoid modifying `active` during pairs() iteration
  local names = {}
  for name in pairs(active) do names[#names + 1] = name end
  for _, name in ipairs(names) do
    modules.disable(name)
  end
end

-- ============================================================
-- Query API
-- ============================================================

--- Get registry entry for a module.
function modules.get(name)
  return registry[name]
end

--- List all installed modules.
-- @return array of { name, version, type, description, author, enabled }
function modules.list()
  local result = {}
  for name, entry in pairs(registry) do
    result[#result + 1] = {
      name        = entry.name,
      version     = entry.version,
      type        = entry.type,
      description = entry.description,
      author      = entry.author,
      enabled     = entry.enabled,
    }
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

--- Get a shell command function provided by an enabled module.
-- @param cmdName string
-- @return function|nil
function modules.getCommand(cmdName)
  for name, mod in pairs(active) do
    if mod.commands and mod.commands[cmdName] then
      return mod.commands[cmdName]
    end
  end
  return nil
end

--- Get all commands from enabled modules.
-- @return table: cmdName -> function
function modules.getCommands()
  local cmds = {}
  for name, mod in pairs(active) do
    if mod.commands then
      for cmdName, fn in pairs(mod.commands) do
        cmds[cmdName] = fn
      end
    end
  end
  return cmds
end

--- Get the install directory for a module.
function modules.getDir(name)
  if not registry[name] then return nil end
  return fs.join(MODULES_DIR, name)
end

--- Scan /usr/modules/ for module dirs that aren't in the registry.
-- Reads module.cfg from each dir and registers them.
-- @return number: count of newly registered modules
function modules.scan()
  if not fs.exists(MODULES_DIR) then return 0 end
  local items = fs.list(MODULES_DIR)
  if not items then return 0 end
  local found = 0
  for _, name in ipairs(items) do
    -- Strip trailing /
    local dirName = name:match("^(.-)/?$")
    if dirName and dirName ~= "" and dirName ~= "registry.dat" then
      local dirPath = fs.join(MODULES_DIR, dirName)
      if fs.isDirectory(dirPath) and not registry[dirName] then
        -- Try to read manifest
        local manifest = modules.readManifest(dirPath)
        if manifest then
          registry[dirName] = {
            name        = manifest.name,
            version     = manifest.version,
            description = manifest.description or "",
            author      = manifest.author or "",
            type        = manifest.type,
            commands    = manifest.commands or {},
            provides    = manifest.provides,
            files       = manifest.files,
            enabled     = false,
            installedAt = os.time and os.time() or 0,
          }
          found = found + 1
          if log then
            log.info("modules", "Scanned: " .. dirName .. " v" .. manifest.version)
          end
        end
      end
    end
  end
  if found > 0 then
    modules.saveRegistry()
  end
  return found
end

return modules
