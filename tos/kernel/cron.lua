local computer = require("computer")
local serialize = require("kernel.serialize")

local cron = {}

local CRON_PATH = "/etc/cron.dat"
local jobs = {}
local nextID = 1
local fs = nil
local log = nil
local event = nil
local timerID = nil

local CRON_CAPS = {
  ["fs.read"]  = true,
  ["fs.write"] = true,
  ["component"] = true,
}

local function sessionForJob(job)
  if not job then return nil end
  local usersmod = nil
  local ok, mod = pcall(require, "kernel.users")
  if ok then usersmod = mod end
  if job.user and usersmod then
    if usersmod.sessionFor then
      local s = usersmod.sessionFor(job.user)
      if s then return s end
    end
    if usersmod.getUser and usersmod.createSession then
      local u = usersmod.getUser(job.user)
      if u then return usersmod.createSession(u) end
    end
  end
  if _G._TOS and _G._TOS.bootSession then return _G._TOS.bootSession end
  if usersmod and usersmod.kernelSession then return usersmod.kernelSession() end
  return nil
end

local function makeSandboxFor(session)
  local sandbox = require("kernel.sandbox")
  return sandbox.build({ caps = CRON_CAPS, session = session })
end

function cron.init(modules)

  if timerID and event then
    pcall(event.cancelTimer, timerID)
    timerID = nil
  end
  fs    = modules.fs
  log   = modules.log
  event = modules.event

  local saved = serialize.loadFile(fs, CRON_PATH)
  if saved then
    jobs = saved.jobs or {}
    nextID = saved.nextID or 1
  end

  if event then
    timerID = event.interval(10, function() cron.tick() end, "kernel:cron")
  end

  if log then
    local count = 0
    for _ in pairs(jobs) do count = count + 1 end
    log.info("cron", "Scheduler initialized (" .. count .. " jobs)")
  end

  return true
end

local function saveJobs()
  serialize.saveFile(fs, CRON_PATH, { jobs = jobs, nextID = nextID })
end

function cron.add(name, intervalSec, script, opts)
  if type(intervalSec) ~= "number" or intervalSec <= 0 then
    return nil, "Invalid interval (must be a positive number)"
  end
  if type(script) ~= "string" or script == "" then
    return nil, "Script must be a non-empty string"
  end

  if #script > 16384 then
    return nil, "cron: script too large (max 16 KB)"
  end

  opts = opts or {}

  local callerUser, callerTier = nil, 0
  do
    local ok, usersmod = pcall(require, "kernel.users")
    if ok and usersmod and usersmod.currentSession then
      local sess = usersmod.currentSession()
      if sess then
        callerUser = sess.user
        callerTier = sess.tier or 0
      end
    end
    if not callerUser and opts.kernelMode
       and _G._TOS and _G._TOS.bootSession then
      callerUser = _G._TOS.bootSession.user
      callerTier = _G._TOS.bootSession.tier or 3
    end
  end
  if not callerUser then
    return nil, "cron: no identity available; refusing to schedule"
  end

  local actorUser = opts.user or callerUser

  if actorUser ~= callerUser and callerTier < 2 then
    return nil, "cron: tier " .. tostring(callerTier) ..
      " cannot schedule jobs as '" .. tostring(actorUser) .. "'"
  end

  if script:sub(1, 1) == "/" then
    local okU, usersmod = pcall(require, "kernel.users")
    if okU and usersmod and usersmod.canAccessAs then
      local sess
      if usersmod.currentSession then sess = usersmod.currentSession() end
      if sess then
        local ok = usersmod.canAccessAs(sess, script, "r")
        if not ok then
          return nil, "cron: caller cannot read '" .. script .. "'"
        end
      end
    end
  end

  local id = nextID
  nextID = nextID + 1
  jobs[id] = {
    name     = name,
    interval = intervalSec,
    script   = script,
    lastRun  = 0,
    enabled  = true,
    user     = actorUser,
  }
  saveJobs()
  if log then
    log.info("cron", string.format("Added job: %s (every %ds, as %s)",
      name, intervalSec, tostring(actorUser or "?")))
  end
  return id
end

function cron.remove(id)
  if not jobs[id] then return false, "No such job" end
  local name = jobs[id].name
  jobs[id] = nil
  saveJobs()
  if log then log.info("cron", "Removed job: " .. name) end
  return true
end

function cron.setEnabled(id, enabled)
  if not jobs[id] then return false end
  jobs[id].enabled = enabled
  saveJobs()
  return true
end

function cron.list()
  local result = {}
  for id, job in pairs(jobs) do
    result[#result + 1] = {
      id       = id,
      name     = job.name,
      interval = job.interval,
      lastRun  = job.lastRun,
      enabled  = job.enabled,
      script   = (job.script or ""):sub(1, 60),
    }
  end
  table.sort(result, function(a, b) return a.id < b.id end)
  return result
end

function cron.tick()
  local now = computer.uptime()

  local envCache = {}

  local secfs = _G._TOS and _G._TOS.securefs

  local procMod
  do local okP, p = pcall(require, "kernel.process"); if okP then procMod = p end end

  for _, job in pairs(jobs) do
    if job.enabled and (now - job.lastRun) >= job.interval then
      job.lastRun = now
      local session = sessionForJob(job)
      if not session then
        if log then
          log.warn("cron", "Job '" .. job.name .. "' skipped: no session for user '" ..
            tostring(job.user) .. "'")
        end
      else
        local userKey = (job.user or "__boot__")
        local env = envCache[userKey]
        if not env then
          env = makeSandboxFor(session)
          envCache[userKey] = env
        end

        local source, srcErr
        local chunkName
        if job.script:match("^/") then
          chunkName = "=" .. job.script
          if secfs and secfs.readFile then
            source, srcErr = secfs.readFile(job.script, session)
          elseif fs then
            source = fs.readFile(job.script)
            if not source then srcErr = "Cannot read: " .. job.script end
          else
            srcErr = "No filesystem available"
          end
        else
          chunkName = "=cron:" .. job.name
          source = job.script
        end

        if not source then
          if log then log.warn("cron", "Job '" .. job.name .. "' read failed: " ..
            tostring(srcErr)) end
        else
          local fn, err = load(source, chunkName, "t", env)
          if not fn then
            if log then log.warn("cron", "Job '" .. job.name .. "' compile error: " ..
              tostring(err)) end
          elseif procMod and procMod.spawn then

            local pid = procMod.spawn("cron:" .. (job.name or "?"), function()
              local pok, perr = pcall(fn)
              if not pok and log then
                log.warn("cron", "Job '" .. job.name .. "' runtime error: " ..
                  tostring(perr))
              end
            end, {
              source    = "cron",
              principal = session,
              priority  = 8,
              tsr       = false,
            })
            if log and pid then
              log.info("cron", "Job '" .. job.name .. "' started as PID " .. tostring(pid))
            end
          else

            local pok, perr = pcall(fn)
            if not pok and log then
              log.warn("cron", "Job '" .. job.name .. "' failed: " .. tostring(perr))
            end
          end
        end
      end
    end
  end
end

function cron.shutdown()
  if timerID and event then
    event.cancelTimer(timerID)
  end
end

do
  local T = rawget(_G, "_TOS")
  if T and T.fs and not fs and not T.cronDisabled then
    pcall(cron.init, { fs = T.fs, log = T.logObj, event = T.event })
  end
end

return cron
