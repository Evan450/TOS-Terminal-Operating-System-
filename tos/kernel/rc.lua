local rc = {}

local RC_DIR = "/etc/rc.d"
local services = {}
local fs = nil
local log = nil
local proc = nil

local DEFAULT_SERVICE_CAPS = {
  ["fs.read"]  = true,
  ["fs.write"] = true,
  ["component"] = true,
  ["net"] = true,
}

local ALLOWED_SERVICE_CAPS = {
  ["fs.read"] = true, ["fs.write"] = true, ["component"] = true,
  ["compat.io"] = true, ["load"] = true, ["net"] = true,

}

local KERNEL_REQUIRE_ALLOW = {
  ["computer"]         = true,
  ["component"]        = true,
  ["kernel.event"]     = true,
  ["kernel.log"]       = true,
  ["kernel.serialize"] = true,
  ["kernel.config"]    = true,
}
local function gatedKernelRequire(modName)
  if type(modName) ~= "string" then
    error("require: module name must be a string", 2)
  end
  if KERNEL_REQUIRE_ALLOW[modName] then
    return require(modName)
  end
  error("rc.d kernel service denied require('" .. modName .. "') (#SEC CR-6)", 2)
end

local function normalizeCaps(spec)
  if type(spec) ~= "table" then
    local out = {}
    for k, v in pairs(DEFAULT_SERVICE_CAPS) do out[k] = v end
    return out
  end
  local out = {}
  for k, v in pairs(spec) do
    local name
    if type(k) == "number" and type(v) == "string" then
      name = v
    elseif type(k) == "string" and v then
      name = k
    end
    if name and ALLOWED_SERVICE_CAPS[name] then
      out[name] = true
    end
  end
  return out
end

local function sessionForUser(userName)
  local ok, usersmod = pcall(require, "kernel.users")
  if not ok or not usersmod then return nil, "users module unavailable" end

  if not userName then
    if _G._TOS and _G._TOS.bootSession then return _G._TOS.bootSession end
    if usersmod.kernelSession then return usersmod.kernelSession() end
    return nil, "no session available"
  end

  if userName == "_kernel_" then
    if usersmod.kernelSession then return usersmod.kernelSession() end
    return nil, "kernelSession unavailable"
  end
  if usersmod.sessionFor then
    local s = usersmod.sessionFor(userName)
    if s then return s end
  end

  if usersmod.getUser then
    local u = usersmod.getUser(userName)
    if u and usersmod.createSession then
      local s = usersmod.createSession(u)
      if s then return s end
    end
  end
  return nil, "unknown user '" .. tostring(userName) .. "'"
end

function rc.init(modules)
  fs   = modules.fs
  log  = modules.log
  proc = modules.proc
end

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

  local allNames = {}
  for name in pairs(svcs) do allNames[#allNames + 1] = name end
  table.sort(allNames)
  for _, n in ipairs(allNames) do visit(n) end
  return sorted
end

function rc.runAll()
  if not fs then return end
  if not fs.exists(RC_DIR) then
    fs.makeDirectory(RC_DIR)
    return
  end

  local files = fs.list(RC_DIR)
  if not files then return end

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

  local function peekServiceMeta(src)

    local meta = {}
    local capsStr = src:match("caps%s*=%s*(%b{})")
    if capsStr then
      meta.caps = {}
      for cap in capsStr:gmatch('"([%w%._]+)"') do
        meta.caps[#meta.caps + 1] = cap
      end
      for cap in capsStr:gmatch("'([%w%._]+)'") do
        meta.caps[#meta.caps + 1] = cap
      end
    end
    meta.user = src:match('user%s*=%s*"([%w_-]+)"')
               or src:match("user%s*=%s*'([%w_-]+)'")

    if meta.user == "_kernel_" then
      meta._kernelClaimed = true
    end
    meta.restart = src:match("restart%s*=%s*true") and true or false
    local mr = src:match("maxRestart%s*=%s*(%d+)")
    if mr then meta.maxRestart = tonumber(mr) end
    return meta
  end

  local loaded = {}

  local KERNEL_SERVICE_ALLOWLIST = {
    ["10-discoveryd"] = true,
    ["20-chatrelay"]  = true,
    ["20-fileshare"]  = true,
    ["20-rshd"]       = true,
  }

  local function kernelTokenOutsideComments(src)
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do

      local code = {}
      local i = 1
      local inS, inD = false, false
      while i <= #line do
        local c = line:sub(i, i)
        if not inS and not inD and c == "-" and line:sub(i+1, i+1) == "-" then
          break
        end
        if not inD and c == "'" and line:sub(i-1, i-1) ~= "\\" then inS = not inS end
        if not inS and c == '"' and line:sub(i-1, i-1) ~= "\\" then inD = not inD end
        code[#code + 1] = c
        i = i + 1
      end
      if table.concat(code):find('"_kernel_"', 1, true)
         or table.concat(code):find("'_kernel_'", 1, true) then
        return true
      end
    end
    return false
  end

  local function buildKernelEnv()
    local env = {

      assert = assert, error = error, pcall = pcall, xpcall = xpcall,
      type = type, tostring = tostring, tonumber = tonumber,
      pairs = pairs, ipairs = ipairs, next = next, select = select,
      rawequal = rawequal, rawlen = rawlen,
      setmetatable = setmetatable, getmetatable = getmetatable,
      math = math, string = string, table = table,
      utf8 = utf8, coroutine = coroutine,
      print = print,
      require = gatedKernelRequire,
      _VERSION = _VERSION,
    }

    if _G._TOS then
      local tos = _G._TOS
      env._TOS = setmetatable({}, {
        __index    = tos,
        __newindex = function(_, k)
          error("_TOS is read-only from rc.d services (key=" .. tostring(k) .. ")", 2)
        end,
        __metatable = false,
      })
    end
    env._G = env
    return env
  end

  for _, name in ipairs(names) do
    local path = RC_DIR .. "/" .. name
    local svcName = name:gsub("%.lua$", "")

    if log then log.info("rc", "Loading: " .. name) end

    local source = fs.readFile(path)
    if source then

      local meta = peekServiceMeta(source)

      if meta._kernelClaimed then
        if not KERNEL_SERVICE_ALLOWLIST[svcName] then
          if log then
            log.warn("rc", "Refusing kernel-tier service '" .. name ..
              "': not in C2 allowlist; demoting to user-tier")
          end
          meta.user = "root"
        elseif not kernelTokenOutsideComments(source) then
          if log then
            log.warn("rc", "Refusing kernel-tier service '" .. name ..
              "': _kernel_ token only appears in comments")
          end
          meta.user = "root"
        end
      end

      local caps = normalizeCaps(meta.caps)
      local session, sessErr = sessionForUser(meta.user)
      if not session then
        if log then
          log.warn("rc", "Skipping '" .. name .. "': " .. tostring(sessErr))
        end
      else
        local svcEnv
        if meta.user == "_kernel_" then
          svcEnv = buildKernelEnv()
        else

          svcEnv = require("kernel.sandbox").build({
            caps = caps, session = session,
            allowUserLibs = true })
        end
        local fn, err = load(source, "=" .. path, "t", svcEnv)
        if fn then
          local ok, result = pcall(fn)
          if ok then
            if type(result) == "table" and result.start then

              local disabledAtBoot = fs.exists(RC_DIR .. "/" .. svcName .. ".disabled")
              services[svcName] = {
                start   = result.start,
                stop    = result.stop,
                running = false,
                disabledAtBoot = disabledAtBoot,
                path    = path,

                deps    = result.deps or {},
                restart = meta.restart or (result.restart and true) or false,
                caps    = caps,
                user    = meta.user,
                restartCount = 0,
                maxRestart   = meta.maxRestart or result.maxRestart or 5,
              }
              loaded[svcName] = result
            else
              loaded[svcName] = true
            end
          else
            if log then log.warn("rc", "Error in " .. name .. ": " .. tostring(result)) end
          end
        else
          if log then log.warn("rc", "Syntax error in " .. name .. ": " .. tostring(err)) end
        end
      end
    end
  end

  local order = topoSort(services)

  for _, svcName in ipairs(order) do
    local svc = services[svcName]
    if svc and svc.disabledAtBoot and not svc.running then

      if log then log.info("rc", "Service registered (disabled): " .. svcName) end
    elseif svc and not svc.running then
      local sok, serr = pcall(svc.start)
      if sok then
        svc.running = true
        if log then log.info("rc", "Service started: " .. svcName) end
      else
        svc.running = false
        svc.lastError = tostring(serr)
        if log then log.warn("rc", "Service start failed: " .. svcName .. ": " .. tostring(serr)) end
      end
    end
  end
end

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

function rc.start(name)
  local svc = services[name]
  if not svc then return false, "Unknown service: " .. name end
  if svc.running then return false, "Already running" end
  local ok, err = pcall(svc.start)
  if ok then
    svc.running = true

    if svc.disabledAtBoot and fs then
      pcall(fs.remove, RC_DIR .. "/" .. name .. ".disabled")
      svc.disabledAtBoot = false
    end
    return true
  end
  return false, tostring(err)
end

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

function rc.list()
  local result = {}
  for name, svc in pairs(services) do
    result[#result + 1] = {
      name         = name,
      running      = svc.running,
      enabled      = not svc.disabledAtBoot,
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

function rc.supervise()
  for name, svc in pairs(services) do
    if svc.running and type(svc.check) == "function" then
      local ok, alive = pcall(svc.check)
      if not ok or not alive then
        svc.running = false
        svc.lastError = (not ok) and tostring(alive) or "check returned false"
      end
    end

    if svc.restart and not svc.running and not svc.disabledAtBoot then
      rc.tryRestart(name)
    end
  end
end

function rc.enable(name, content)
  if not fs then return false end
  if not fs.exists(RC_DIR) then fs.makeDirectory(RC_DIR) end
  return fs.writeFile(RC_DIR .. "/" .. name .. ".lua", content)
end

function rc.disable(name)
  if not fs then return false end
  rc.stop(name)
  return fs.remove(RC_DIR .. "/" .. name .. ".lua")
end

rc._gatedKernelRequire    = gatedKernelRequire
rc._KERNEL_REQUIRE_ALLOW  = KERNEL_REQUIRE_ALLOW

return rc
