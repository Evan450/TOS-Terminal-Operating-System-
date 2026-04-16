-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Scheduled Tasks      ║
-- ║  Timer-based job execution         ║
-- ╚══════════════════════════════════════╝
-- Lightweight cron-like scheduler. Jobs are stored in /etc/cron.dat
-- and checked every tick by a kernel interval timer.

local computer = require("computer")
local serialize = require("kernel.serialize")

local cron = {}

local CRON_PATH = "/etc/cron.dat"
local jobs = {}       -- id -> { interval, lastRun, script, name, enabled }
local nextID = 1
local fs = nil
local log = nil
local event = nil
local timerID = nil

-- Build a restricted environment for cron job execution.
-- Jobs get standard Lua + OC APIs but not kernel internals.
local function makeSandbox()
  -- Shallow-copy mutable libraries so jobs cannot poison the host
  local function copyLib(lib)
    local c = {}
    for k, v in pairs(lib) do c[k] = v end
    return c
  end
  local env = {
    -- Lua builtins (safe subset -- no require/load/dofile/io)
    assert = assert, error = error, pcall = pcall, xpcall = xpcall,
    type = type, tostring = tostring, tonumber = tonumber,
    pairs = pairs, ipairs = ipairs, next = next, select = select,
    setmetatable = setmetatable, getmetatable = getmetatable,
    print = print,
    -- Standard libraries (copies to prevent host poisoning)
    math = copyLib(math), string = copyLib(string), table = copyLib(table),
    os = { clock = os.clock, time = os.time, date = os.date },
    -- OC globals
    computer = {
      uptime = computer.uptime,
      freeMemory = computer.freeMemory,
      totalMemory = computer.totalMemory,
      beep = computer.beep,
    },
  }
  -- Provide fs access if available (read + write for maintenance jobs)
  if fs then
    env.fs = {
      exists = fs.exists, list = fs.list, isDirectory = fs.isDirectory,
      readFile = fs.readFile, writeFile = fs.writeFile,
    }
  end
  env._G = env
  return env
end

function cron.init(modules)
  fs    = modules.fs
  log   = modules.log
  event = modules.event

  -- Load saved jobs
  if fs and fs.exists(CRON_PATH) then
    local data = fs.readFile(CRON_PATH)
    if data then
      local saved = serialize.decode(data)
      if saved then
        jobs = saved.jobs or {}
        nextID = saved.nextID or 1
      end
    end
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
  if not fs then return end
  local data = serialize.encode({ jobs = jobs, nextID = nextID })
  fs.writeFile(CRON_PATH, data)
end

--- Add a recurring job.
-- @param name string: Human-readable name
-- @param intervalSec number: Seconds between runs
-- @param script string: Lua code to execute OR path to a .lua file
-- @return number: Job ID
function cron.add(name, intervalSec, script)
  if type(intervalSec) ~= "number" or intervalSec <= 0 then
    return nil, "Invalid interval (must be a positive number)"
  end
  if type(script) ~= "string" or script == "" then
    return nil, "Script must be a non-empty string"
  end
  local id = nextID
  nextID = nextID + 1
  jobs[id] = {
    name     = name,
    interval = intervalSec,
    script   = script,
    lastRun  = 0,
    enabled  = true,
  }
  saveJobs()
  if log then log.info("cron", "Added job: " .. name .. " (every " .. intervalSec .. "s)") end
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
  for id, job in pairs(jobs) do
    if job.enabled and (now - job.lastRun) >= job.interval then
      job.lastRun = now
      local ok, err
      -- If script looks like a file path, load and run it
      local sandbox = makeSandbox()
      if job.script:match("^/") and fs then
        local source = fs.readFile(job.script)
        if source then
          local fn
          fn, err = load(source, "=" .. job.script, "t", sandbox)
          if fn then ok, err = pcall(fn) end
        else
          err = "Cannot read: " .. job.script
        end
      else
        -- Inline Lua code
        local fn
        fn, err = load(job.script, "=cron:" .. job.name, "t", sandbox)
        if fn then ok, err = pcall(fn) end
      end
      if not ok and log then
        log.warn("cron", "Job '" .. job.name .. "' failed: " .. tostring(err))
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

return cron
