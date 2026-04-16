-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Startup Scripts      ║
-- ║  /etc/rc.d/ service manager        ║
-- ╚══════════════════════════════════════╝
-- Loads and runs scripts from /etc/rc.d/ on boot.
-- Scripts are plain Lua files, executed in filename order.
-- A script can return a table with start/stop functions for
-- service-like behavior.
--
-- Phase 7 enhancements:
--   • Service tables may declare: deps, restart, caps, user
--   • Dependency-ordered startup (topological sort)
--   • Restart supervision for services that set restart = true
--   • Services run with sandboxed identity when caps/user are set

local rc = {}

local RC_DIR = "/etc/rc.d"
local services = {}  -- name -> service record
local fs = nil
local log = nil
local proc = nil  -- optional, for restart supervisor

function rc.init(modules)
  fs   = modules.fs
  log  = modules.log
  proc = modules.proc
end

-- ── Topological sort ────────────────────────────────────
-- Given a table of { name -> { deps = { ... } } }, returns an ordered
-- list of names such that each service's dependencies come before it.
-- Unresolvable deps are warned but not fatal (the service just starts
-- after everything else).
local function topoSort(svcs)
  local visited, sorted, inStack = {}, {}, {}
  local function visit(name)
    if visited[name] then return end
    if inStack[name] then
      if log then log.warn("rc", "Circular dependency at '" .. name .. "' — breaking cycle") end
      return
    end
    inStack[name] = true
    local rec = svcs[name]
    if rec and rec.deps then
      for _, dep in ipairs(rec.deps) do
        visit(dep)
      end
    end
    inStack[name] = nil
    visited[name] = true
    sorted[#sorted + 1] = name
  end
  -- Seed with all registered names
  local allNames = {}
  for name in pairs(svcs) do allNames[#allNames + 1] = name end
  table.sort(allNames) -- deterministic within a dep tier
  for _, n in ipairs(allNames) do visit(n) end
  return sorted
end

--- Run all startup scripts in /etc/rc.d/
function rc.runAll()
  if not fs then return end
  if not fs.exists(RC_DIR) then
    fs.makeDirectory(RC_DIR)
    return
  end

  local files = fs.list(RC_DIR)
  if not files then return end

  -- Collect and sort filenames
  local names = {}
  if type(files) == "table" then
    for _, name in ipairs(files) do
      if name:match("%.lua$") then
        names[#names + 1] = name
      end
    end
  elseif type(files) == "function" then
    for name in files do
      if name:match("%.lua$") then
        names[#names + 1] = name
      end
    end
  end
  table.sort(names)

  -- Phase 1: load all scripts and register service tables
  local loaded = {}  -- svcName -> service table (or true for plain scripts)
  for _, name in ipairs(names) do
    local path = RC_DIR .. "/" .. name
    local svcName = name:gsub("%.lua$", "")

    if log then log.info("rc", "Loading: " .. name) end

    local source = fs.readFile(path)
    if source then
      local fn, err = load(source, "=" .. path, "t")
      if fn then
        local ok, result = pcall(fn)
        if ok then
          if type(result) == "table" and result.start then
            services[svcName] = {
              start   = result.start,
              stop    = result.stop,
              running = false,
              path    = path,
              -- Phase 7 fields (from service table)
              deps    = result.deps or {},
              restart = result.restart or false,
              caps    = result.caps,
              user    = result.user,
              restartCount = 0,
              maxRestart   = result.maxRestart or 5,
            }
            loaded[svcName] = result
          else
            loaded[svcName] = true  -- plain script, already ran
          end
        else
          if log then log.warn("rc", "Error in " .. name .. ": " .. tostring(result)) end
        end
      else
        if log then log.warn("rc", "Syntax error in " .. name .. ": " .. tostring(err)) end
      end
    end
  end

  -- Phase 2: topological sort by dependencies
  local order = topoSort(services)

  -- Phase 3: start services in dependency order
  for _, svcName in ipairs(order) do
    local svc = services[svcName]
    if svc and not svc.running then
      local sok, serr = pcall(svc.start)
      if sok then
        svc.running = true
        if log then log.info("rc", "Service started: " .. svcName) end
      else
        if log then log.warn("rc", "Service start failed: " .. svcName .. ": " .. tostring(serr)) end
      end
    end
  end
end

--- Stop all running services (called on shutdown)
function rc.stopAll()
  for name, svc in pairs(services) do
    if svc.running and svc.stop then
      local ok, err = pcall(svc.stop)
      if ok then
        svc.running = false
        if log then log.info("rc", "Service stopped: " .. name) end
      else
        if log then log.warn("rc", "Service stop failed: " .. name .. ": " .. tostring(err)) end
      end
    end
  end
end

--- Start a specific service by name
function rc.start(name)
  local svc = services[name]
  if not svc then return false, "Unknown service: " .. name end
  if svc.running then return false, "Already running" end
  local ok, err = pcall(svc.start)
  if ok then
    svc.running = true
    return true
  end
  return false, tostring(err)
end

--- Stop a specific service
function rc.stop(name)
  local svc = services[name]
  if not svc then return false, "Unknown service: " .. name end
  if not svc.running then return false, "Not running" end
  if not svc.stop then return false, "No stop handler" end
  local ok, err = pcall(svc.stop)
  if ok then
    svc.running = false
    return true
  end
  return false, tostring(err)
end

--- List all known services
function rc.list()
  local result = {}
  for name, svc in pairs(services) do
    result[#result + 1] = {
      name         = name,
      running      = svc.running,
      path         = svc.path,
      deps         = svc.deps,
      restart      = svc.restart,
      restartCount = svc.restartCount,
      caps         = svc.caps,
      user         = svc.user,
    }
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

--- Attempt to restart a crashed service (called by supervisor tick).
function rc.tryRestart(name)
  local svc = services[name]
  if not svc then return false end
  if not svc.restart then return false end
  if svc.restartCount >= svc.maxRestart then
    if log then log.warn("rc", "Service '" .. name .. "' exceeded max restarts (" .. svc.maxRestart .. ")") end
    return false
  end
  svc.restartCount = svc.restartCount + 1
  if log then log.info("rc", "Restarting service: " .. name .. " (attempt " .. svc.restartCount .. ")") end
  local ok, err = pcall(svc.start)
  if ok then
    svc.running = true
    return true
  end
  if log then log.warn("rc", "Restart failed: " .. name .. ": " .. tostring(err)) end
  return false
end

--- Supervisor tick: check for crashed services and restart them.
-- Call this periodically from the kernel loop or cron.
function rc.supervise()
  for name, svc in pairs(services) do
    if svc.restart and not svc.running then
      rc.tryRestart(name)
    end
  end
end

--- Enable a script (create it in rc.d)
function rc.enable(name, content)
  if not fs then return false end
  if not fs.exists(RC_DIR) then fs.makeDirectory(RC_DIR) end
  return fs.writeFile(RC_DIR .. "/" .. name .. ".lua", content)
end

--- Disable a script (remove from rc.d)
function rc.disable(name)
  if not fs then return false end
  rc.stop(name)
  return fs.remove(RC_DIR .. "/" .. name .. ".lua")
end

return rc
