-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Scheduled Tasks        ║
-- ║  Timer-based job execution           ║
-- ╚══════════════════════════════════════╝
-- Lightweight cron-like scheduler. Jobs are stored in /etc/cron.dat
-- and checked every tick by a kernel interval timer.

local computer = require("computer")
local serialize = require("kernel.serialize")

local cron = {}

local CRON_PATH = "/etc/cron.dat"
local jobs = {}       -- id -> { interval, lastRun, script, name, enabled, user }
local nextID = 1
local fs = nil
local log = nil
local event = nil
local timerID = nil

-- Caps granted to every cron job. Deliberately modest: a cron job that
-- needs more than this (e.g. net) should be scheduled via a wrapping
-- rc.d service. The sandbox is bound to the scheduling user's session,
-- so fs ops are enforced against that user's ACL — NOT root's.
local CRON_CAPS = {
  ["fs.read"]  = true,
  ["fs.write"] = true,
  ["component"] = true,
}

-- Resolve the session to run a job as. Prefers the user recorded when
-- the job was scheduled (so admin-created jobs don't suddenly run as
-- root once root logs in). Falls back to the kernel boot session.
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

-- Build a sandbox env for a given session. Cached per-tick so that
-- multiple jobs running as the same user share one env build
-- (previously every job got its own fresh env every firing).
local function makeSandboxFor(session)
  local sandbox = require("kernel.sandbox")
  return sandbox.build({ caps = CRON_CAPS, session = session })
end

function cron.init(modules)
  -- #MEM — re-init safe: the module can now self-initialize on load (lazy
  -- path below) and STILL receive an explicit init() from the kernel or a
  -- test. Cancel any previous tick timer first so a second init can't
  -- leave two schedulers running.
  if timerID and event then
    pcall(event.cancelTimer, timerID)
    timerID = nil
  end
  fs    = modules.fs
  log   = modules.log
  event = modules.event

  -- Load saved jobs
  local saved = serialize.loadFile(fs, CRON_PATH)
  if saved then
    jobs = saved.jobs or {}
    nextID = saved.nextID or 1
  end

  -- Register a kernel interval timer to check jobs
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

--- Add a recurring job.
-- @param name string: Human-readable name
-- @param intervalSec number: Seconds between runs
-- @param script string: Lua code to execute OR path to a .lua file
-- @param opts table|nil: { user = "alice" } to override the actor.
--        If omitted, the current session's user is recorded — so the
--        job runs under the identity of whoever scheduled it, not as
--        whoever happens to be logged in when the timer fires.
--        Setting opts.user to a different user than the caller requires
--        ADMIN tier (>=2). A normal user can only schedule jobs that
--        will run as themselves.
-- @return number: Job ID
function cron.add(name, intervalSec, script, opts)
  if type(intervalSec) ~= "number" or intervalSec <= 0 then
    return nil, "Invalid interval (must be a positive number)"
  end
  if type(script) ~= "string" or script == "" then
    return nil, "Script must be a non-empty string"
  end
  -- #SEC H12 — enforce a script size ceiling at insertion time. Cron
  -- jobs run in the timer-callback context (no per-tick supervisor),
  -- so a 1MB inline script (or a path pointing at a multi-megabyte
  -- file) would consume the whole tick budget. Reject obviously
  -- pathological inputs up front.
  if #script > 16384 then
    return nil, "cron: script too large (max 16 KB)"
  end

  opts = opts or {}

  -- Resolve the caller's identity. Every scheduling call must be
  -- attributable — anonymous jobs are refused.
  --
  -- #SEC H11 — the boot-session fallback used to fire whenever no live
  -- session resolved, which let a listener registered during boot
  -- schedule jobs as root from a callback that fired AFTER boot
  -- completed. We now require an explicit `kernelMode = true` opt for
  -- boot-time callers to claim that fallback; everyone else gets the
  -- normal nil-session refusal path.
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
  -- Enforce: scheduling as someone other than yourself requires ADMIN.
  if actorUser ~= callerUser and callerTier < 2 then
    return nil, "cron: tier " .. tostring(callerTier) ..
      " cannot schedule jobs as '" .. tostring(actorUser) .. "'"
  end

  -- #SEC H12 — if `script` is a path, validate canRead AT INSERTION
  -- time as the caller (not the actor). A USER scheduling a job as
  -- themselves shouldn't be able to register `/etc/users.dat` and then
  -- have cron read it on their behalf at tick time.
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

--- Remove a job.
function cron.remove(id)
  if not jobs[id] then return false, "No such job" end
  local name = jobs[id].name
  jobs[id] = nil
  saveJobs()
  if log then log.info("cron", "Removed job: " .. name) end
  return true
end

--- Enable/disable a job.
function cron.setEnabled(id, enabled)
  if not jobs[id] then return false end
  jobs[id].enabled = enabled
  saveJobs()
  return true
end

--- List all jobs.
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

--- Execute pending jobs (called by interval timer).
function cron.tick()
  local now = computer.uptime()
  -- Per-tick sandbox cache keyed by user. Jobs owned by the same user
  -- share one env build; jobs for different users still get their own.
  local envCache = {}
  -- Use a securefs proxy for reading script files so a job scheduled
  -- by a non-admin can't resolve a path that user has no read access to.
  local secfs = _G._TOS and _G._TOS.securefs

  -- #SEC M28 — spawn cron jobs via proc.spawn instead of running them
  -- inline in the timer callback. Two wins:
  --   1. An infinite-loop job can be killed (`kill <pid>`) without
  --      taking down the kernel. Inline execution wedged everything.
  --   2. CPU is properly accounted; `ps` shows the job among other
  --      processes; the scheduler's preemptive yield (when enabled)
  --      will kick in.
  -- Falls through to the old inline path only when proc.spawn isn't
  -- available (very early boot, no process subsystem yet).
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

        -- Resolve source body up front (file path or inline code).
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
            -- Spawn as a real process so it's killable + accounted.
            local pid = procMod.spawn("cron:" .. (job.name or "?"), function()
              local pok, perr = pcall(fn)
              if not pok and log then
                log.warn("cron", "Job '" .. job.name .. "' runtime error: " ..
                  tostring(perr))
              end
            end, {
              source    = "cron",
              principal = session,
              priority  = 8,  -- low-priority by default
              tsr       = false,
            })
            if log and pid then
              log.info("cron", "Job '" .. job.name .. "' started as PID " .. tostring(pid))
            end
          else
            -- Fallback: inline execution. Same behavior as before
            -- M28 — used only when the process subsystem isn't ready.
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

--- Shutdown: cancel the timer
function cron.shutdown()
  if timerID and event then
    event.cancelTimer(timerID)
  end
end

-- #MEM — lazy self-initialization. When no /etc/cron.dat exists the kernel
-- skips the scheduler at boot entirely; the first `cron` command loads this
-- module (shell paths pcall(require, "kernel.cron") directly) and this
-- block brings it up from the live _TOS handles — including registering
-- the tick timer, so a job added now runs without a reboot. Off-box tests
-- (no _TOS.fs) keep using explicit init().
-- #SEC — a boot profile that gates cron OFF (Safe Mode, minimal) sets
-- _TOS.cronDisabled. Honor it here, or the first `cron` command would
-- self-init the scheduler and start running saved jobs on a boot whose
-- whole point was that no stored job code runs.
do
  local T = rawget(_G, "_TOS")
  if T and T.fs and not fs and not T.cronDisabled then
    pcall(cron.init, { fs = T.fs, log = T.logObj, event = T.event })
  end
end

return cron
