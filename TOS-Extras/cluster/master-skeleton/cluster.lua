-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster — Operator CLI                                      ║
-- ║  Invoked from the shell; dispatches subcommands via          ║
-- ║  cluster.api which talks to the running clusterd.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Access tier enforcement (via TOS's users module):
--   ADMIN: read-only commands (status, managers, jobs, storage, log)
--   ROOT : mutating commands  (submit, cancel, retry, drain, undrain,
--                                forget, config set)
--
-- Dispatch shim is intentionally small: print formatting lives here,
-- domain logic lives in cluster.api.

local api   = require("cluster.api")
local users = require("users")  -- TOS user/tier check

-- Optional modules: guard against running outside a full shell.
local term, event
do
  local ok, mod = pcall(require, "term");  term  = ok and mod or nil
  local ok2, mod2 = pcall(require, "event"); event = ok2 and mod2 or nil
end

local cli = {}

-- ============================================================
-- Output helpers
-- ============================================================

local function die(msg)
  io.stderr:write("cluster: " .. tostring(msg) .. "\n")
  os.exit(1)
end

local function _tierName(t)
  local map = { [0]="GUEST", [1]="USER", [2]="ADMIN", [3]="ROOT" }
  return map[t] or ("tier" .. tostring(t))
end

-- ============================================================
-- Tier guard
-- ============================================================

local function requireTier(minName)
  if not users or not users.TIER or not users.currentSession then
    -- Users module missing → fail closed rather than allow unchecked access.
    die("users subsystem unavailable; refusing to run")
  end
  local need = users.TIER[minName]
  if not need then die("internal: unknown tier " .. tostring(minName)) end

  local sess = users.currentSession()
  if not sess then
    die("not logged in")
  end
  local have = sess.tier or 0
  if have < need then
    io.stderr:write(string.format(
      "cluster: permission denied (need %s, have %s)\n",
      minName, _tierName(have)))
    os.exit(1)
  end
end

local function _fmtTime(t)
  if not t then return "-" end
  local now = require("computer").uptime()
  local d   = math.floor(now - t)
  if d < 0 then return "-" end
  if d < 60 then return d .. "s ago" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  return math.floor(d / 3600) .. "h ago"
end

local function _padRight(s, w)
  s = tostring(s or "")
  if #s >= w then return s:sub(1, w) end
  return s .. string.rep(" ", w - #s)
end

local function _padLeft(s, w)
  s = tostring(s or "")
  if #s >= w then return s:sub(-w) end
  return string.rep(" ", w - #s) .. s
end

local function _cellValue(row, col)
  -- Allow synthetic columns ("workers", "storage") that need computing.
  if col.key == "workers" then
    local snap = row.last_snapshot
    if not snap then return "-/-" end
    return tostring(snap.workers_busy or 0) .. "/" ..
           tostring(snap.workers_active or 0)
  elseif col.key == "queue" then
    return row.last_snapshot and tostring(row.last_snapshot.queue_depth or 0) or "-"
  elseif col.key == "storage" then
    local s = row.storage or {}
    local t = s.external_type or "-"
    return tostring(t):sub(1, 6)
  elseif col.key == "submitted_at" then
    return _fmtTime(row.submitted_at)
  end
  return row[col.key]
end

local function printTable(rows, columns)
  if not rows or #rows == 0 then
    print("(no entries)")
    return
  end
  -- Header
  local hdr = {}
  for _, c in ipairs(columns) do
    local fn = (c.align == "right") and _padLeft or _padRight
    hdr[#hdr + 1] = fn(c[2] or c.header, c[3] or c.width or 10)
  end
  print(table.concat(hdr, "  "))

  -- Divider
  local div = {}
  for _, c in ipairs(columns) do
    div[#div + 1] = string.rep("-", c[3] or c.width or 10)
  end
  print(table.concat(div, "  "))

  -- Body
  for _, r in ipairs(rows) do
    local line = {}
    for _, c in ipairs(columns) do
      local col = { key = c[1] or c.key, align = c[4] or c.align }
      local fn  = (col.align == "right") and _padLeft or _padRight
      line[#line + 1] = fn(tostring(_cellValue(r, col) or "-"), c[3] or c.width or 10)
    end
    print(table.concat(line, "  "))
  end
end

local function printKV(obj, order)
  if not obj then print("(nil)"); return end
  local seen = {}
  if order then
    for _, k in ipairs(order) do
      if obj[k] ~= nil then
        print(string.format("%-20s %s", k .. ":", tostring(obj[k])))
        seen[k] = true
      end
    end
  end
  for k, v in pairs(obj) do
    if not seen[k] and type(v) ~= "table" and type(v) ~= "function" then
      print(string.format("%-20s %s", k .. ":", tostring(v)))
    end
  end
end

-- ============================================================
-- Subcommand: status
-- ============================================================

function cli.status(_args)
  requireTier("ADMIN")
  local s = api.status()
  if not s then die("daemon not responding") end

  print(string.format("Managers:  %d active   %d degraded   %d draining   %d offline",
    s.managers.active or 0, s.managers.degraded or 0,
    s.managers.draining or 0, s.managers.offline or 0))
  print(string.format("Jobs:      %d pending  %d running    %d done       %d failed   %d cancelled",
    s.jobs.pending or 0, s.jobs.running or 0,
    s.jobs.done or 0, s.jobs.failed or 0, s.jobs.cancelled or 0))
  if s.storage then
    local used = s.storage.used_bytes or 0
    local cap  = s.storage.capacity_bytes or 0
    print(string.format("Storage:   configured, %d / %d bytes used", used, cap))
  else
    print("Storage:   not configured")
  end
  print(string.format("Budget:    host_thread_budget=%s, in_flight=%d",
    tostring(s.host_thread_budget), s.compute_bound_in_flight or 0))
end

-- ============================================================
-- Subcommand: managers
-- ============================================================

function cli.managers(args)
  requireTier("ADMIN")
  if args[1] then
    local domain_id = tonumber(args[1]) or die("invalid domain_id: " .. args[1])
    local m = api.getManager(domain_id)
    if not m then die("no such domain: " .. domain_id) end
    printKV(m, {"hostname","domain_id","state","profile","worker_count",
                "master_path","last_heartbeat","cluster_protocol","software_version"})
    if m.storage then
      print("storage:")
      printKV(m.storage)
    end
    if m.last_snapshot then
      print("last snapshot:")
      printKV(m.last_snapshot)
    end
  else
    local list = api.listManagers()
    printTable(list, {
      {"domain_id", "DOM",      5,  "right"},
      {"hostname",  "HOSTNAME", 16, "left"},
      {"state",     "STATE",    10, "left"},
      {"profile",   "PROFILE",  8,  "left"},
      {"workers",   "WORKERS",  10, "left"},
      {"queue",     "QUEUE",    6,  "right"},
      {"storage",   "STOR",     6,  "left"},
    })
  end
end

-- ============================================================
-- Subcommand: jobs
-- ============================================================

function cli.jobs(args)
  requireTier("ADMIN")
  if args[1] then
    local job_id = tonumber(args[1]) or die("invalid job_id: " .. args[1])
    local j = api.getJob(job_id)
    if not j then die("no such job: " .. job_id) end
    printKV(j, {"job_id","state","submitted_by","compute_profile","retry_policy",
                "result_sink","storage_preference"})
    print("")
    print("Assignments:")
    printTable(j.assignments_list or {}, {
      {"assignment_id", "AID",     5,  "right"},
      {"state",         "STATE",   12, "left"},
      {"attempts",      "ATT",     4,  "right"},
      {"assigned_to",   "MGR",     18, "left"},
      {"dispatched_at", "START",   12, "left"},
    })
  else
    local list = api.listJobs()
    printTable(list, {
      {"job_id",       "JOB",   5,  "right"},
      {"state",        "STATE", 11, "left"},
      {"submitted_by", "USER",  10, "left"},
      {"submitted_at", "AT",    12, "left"},
      {"assignments",  "A",     7,  "left"},
    })
  end
end

-- ============================================================
-- Subcommand: storage
-- ============================================================

function cli.storage(_args)
  requireTier("ADMIN")
  local s = api.storageStatus()
  if not s then
    print("Public storage: not configured")
    return
  end
  printKV(s, {"address", "used_bytes", "capacity_bytes", "last_seen"})
end

-- ============================================================
-- Subcommand: submit
-- ============================================================

function cli.submit(args)
  requireTier("ROOT")
  local path = args[1] or die("usage: cluster submit <job-file>")
  local chunk, err = loadfile(path, "t")
  if not chunk then die("loadfile failed: " .. tostring(err)) end
  local ok, spec = pcall(chunk)
  if not ok then die("job file threw: " .. tostring(spec)) end
  if type(spec) ~= "table" then die("job file must return a table") end

  local job_id, serr = api.submit(spec)
  if not job_id then die(tostring(serr)) end
  print("Submitted job " .. tostring(job_id))
end

-- ============================================================
-- Subcommand: cancel / retry
-- ============================================================

function cli.cancel(args)
  requireTier("ROOT")
  local job_id = tonumber(args[1]) or die("usage: cluster cancel <job_id>")
  local ok, err = api.cancelJob(job_id)
  if not ok then die(tostring(err)) end
  print("Cancelled job " .. tostring(job_id))
end

function cli.retry(args)
  requireTier("ROOT")
  local job_id = tonumber(args[1]) or die("usage: cluster retry <job_id>")
  local new_id, err = api.retryJob(job_id)
  if not new_id then die(tostring(err)) end
  print("Retried as job " .. tostring(new_id))
end

-- ============================================================
-- Subcommand: drain / undrain / forget
-- ============================================================

function cli.drain(args)
  requireTier("ROOT")
  local domain_id = tonumber(args[1]) or die("usage: cluster drain <domain_id>")
  local ok, err = api.drainManager(domain_id)
  if not ok then die(tostring(err)) end
  print("Draining domain " .. tostring(domain_id))
end

function cli.undrain(args)
  requireTier("ROOT")
  local domain_id = tonumber(args[1]) or die("usage: cluster undrain <domain_id>")
  local ok, err = api.undrainManager(domain_id)
  if not ok then die(tostring(err)) end
  print("Domain " .. tostring(domain_id) .. " active")
end

function cli.forget(args)
  requireTier("ROOT")
  local domain_id = tonumber(args[1]) or die("usage: cluster forget <domain_id>")
  local ok, err = api.forgetManager(domain_id)
  if not ok then die(tostring(err)) end
  print("Forgot domain " .. tostring(domain_id))
end

-- ============================================================
-- Subcommand: pair (trust bootstrap; CLUSTER-6)
-- ============================================================
-- Opens a one-time pairing window. Operator reads the displayed code,
-- walks to each Manager, and types it into `cluster-manager pair`.
-- The pairing exchange runs over CLUSTER_PAIR_INIT / _CONFIRM packets,
-- which trust.lua allows at UNKNOWN level (chicken-and-egg solved).

function cli.pair(args)
  requireTier("ROOT")
  local sub = args[1] or "start"

  if sub == "start" then
    local window, err = api.startPairing()
    if not window then
      die("pair start failed: " .. tostring(err or "unknown"))
    end
    print("Pairing window open.")
    print("")
    print("  Code: " .. window.code)
    print("")
    print(string.format(
      "Expires in %d seconds. On each Manager run:",
      math.floor(window.expires_in)))
    print("  cluster-manager pair <master-addr> " .. window.code)
    print("")
    print("Use `cluster pair status` to check progress, `cluster pair close` to end.")

  elseif sub == "status" then
    local info = api.pairingInfo()
    if not info then
      print("No pairing window open.")
      return
    end
    print(string.format("Pairing window open: %d seconds remaining",
      math.floor(info.expires_in)))
    print(string.format("Managers paired so far: %d", info.paired or 0))

  elseif sub == "close" then
    if api.closePairing() then
      print("Pairing window closed.")
    else
      print("No pairing window was open.")
    end

  else
    print("Usage: cluster pair [start|status|close]")
    print("  start   open a 5-minute pairing window and print the code")
    print("  status  show remaining time + how many managers paired")
    print("  close   close the active window early")
  end
end

-- ============================================================
-- Subcommand: watch (simple TUI dashboard)
-- ============================================================

function cli.watch(args)
  requireTier("ADMIN")
  if not term or not term.clear then
    die("watch requires a terminal")
  end

  -- Parse args: --interval N, --events N.
  local interval = 1.0
  local eventCount = 8
  for i = 1, #args do
    if args[i] == "--interval" and args[i + 1] then
      interval = tonumber(args[i + 1]) or 1.0
    elseif args[i] == "--events" and args[i + 1] then
      eventCount = tonumber(args[i + 1]) or 8
    end
  end
  if interval < 0.2 then interval = 0.2 end
  if interval > 60 then interval = 60 end

  local computer = require("computer")

  -- CLUSTER-4 — render a compact dashboard frame. Sections are
  -- ASCII-rule-separated so it reads on T1 monochrome too.
  local function rule(label)
    -- 60-wide rule keeps the dashboard sane on smaller terms.
    print(string.format("── %s ", label) .. string.rep("─", 56 - #label))
  end

  print("Watching cluster. Refresh = " .. interval .. "s. Press 'q' to quit.")
  while true do
    term.clear()

    -- Header line: cluster summary as a one-liner.
    local s = api.status()
    local mgrs = s.managers or {}
    local jobs = s.jobs or {}
    print(string.format(
      "Cluster | mgrs: active=%d degr=%d drain=%d off=%d | jobs: pend=%d run=%d done=%d fail=%d | cb_in_flight=%d budget=%s",
      mgrs.active or 0, mgrs.degraded or 0, mgrs.draining or 0, mgrs.offline or 0,
      jobs.pending or 0, jobs.running or 0, jobs.done or 0, jobs.failed or 0,
      s.compute_bound_in_flight or 0,
      tostring(s.host_thread_budget or "?")))

    -- Storage line, if configured.
    if s.storage then
      print(string.format("Storage | %s used=%s/%s last_seen=%s",
        s.storage.address and s.storage.address:sub(1, 8) .. "..." or "?",
        tostring(s.storage.used_bytes or "?"),
        tostring(s.storage.capacity_bytes or "?"),
        tostring(s.storage.last_seen or "?")))
    end

    print("")
    rule("Managers")
    cli.managers({})

    print("")
    rule("Recent jobs")
    cli.jobs({})

    -- Events panel — new in CLUSTER-4. Pulled from state.recentEvents
    -- via the API; sorted newest-last so the bottom of the screen has
    -- the freshest activity.
    print("")
    rule("Events (newest last)")
    local events = api.recentEvents(eventCount) or {}
    if #events == 0 then
      print("  (no recent events)")
    else
      for _, ev in ipairs(events) do
        local detail = ""
        if type(ev.detail) == "table" then
          local parts = {}
          for k, v in pairs(ev.detail) do parts[#parts + 1] = k .. "=" .. tostring(v) end
          detail = " " .. table.concat(parts, " ")
        end
        print(string.format("  [%.1fs] %s%s",
          ev.time or 0, tostring(ev.kind), detail))
      end
    end

    -- Footer hint.
    print("")
    print("  q=quit | --interval Ns | --events N")

    -- Wait for either the refresh interval or a 'q' key.
    local quit = false
    if event and event.pull then
      local t0 = computer.uptime()
      while computer.uptime() - t0 < interval do
        local remaining = interval - (computer.uptime() - t0)
        if remaining <= 0 then break end
        local name, _, ch = event.pull(math.min(0.25, remaining), "key_down")
        if name == "key_down" then
          if ch == 113 or ch == 81 then quit = true; break end -- q / Q
        end
      end
    end
    if quit then break end
  end
  if term and term.clear then term.clear() end
end

-- ============================================================
-- Subcommand: config
-- ============================================================

function cli.config(args)
  if args[1] == "set" then
    requireTier("ROOT")
    local k, v = args[2], args[3]
    if not k or v == nil then die("usage: cluster config set <key> <value>") end
    local ok, info = api.setConfig(k, v)
    if not ok then die(tostring(info)) end
    if info and info.restart_required then
      print("Set " .. k .. "; restart required for the change to take effect.")
    else
      print("Set " .. k .. ".")
    end
  else
    requireTier("ADMIN")
    local cfg = api.getConfig()
    printKV(cfg)
  end
end

-- ============================================================
-- Subcommand: log
-- ============================================================

function cli.log(args)
  requireTier("ADMIN")
  local n = tonumber(args[1]) or 20
  local events = api.recentEvents(n)
  if not events or #events == 0 then
    print("(no recent events)")
    return
  end
  for _, ev in ipairs(events) do
    local detail = ""
    if type(ev.detail) == "table" then
      local parts = {}
      for k, v in pairs(ev.detail) do
        parts[#parts + 1] = k .. "=" .. tostring(v)
      end
      detail = " " .. table.concat(parts, " ")
    end
    print(string.format("[%s] %s%s", _fmtTime(ev.time), tostring(ev.kind), detail))
  end
end

-- ============================================================
-- Dispatch
-- ============================================================

local SUBCOMMANDS = {
  status   = cli.status,
  managers = cli.managers,
  jobs     = cli.jobs,
  storage  = cli.storage,
  submit   = cli.submit,
  cancel   = cli.cancel,
  retry    = cli.retry,
  drain    = cli.drain,
  undrain  = cli.undrain,
  forget   = cli.forget,
  watch    = cli.watch,
  config   = cli.config,
  log      = cli.log,
  pair     = cli.pair,
}

local function usage()
  print("Usage: cluster <subcommand> [args...]")
  print("Subcommands:")
  print("  status                Cluster summary")
  print("  managers [domain_id]  List managers / show one")
  print("  jobs [job_id]         List jobs / show one")
  print("  storage               Public storage status")
  print("  submit <file>         Submit a job")
  print("  cancel <job_id>       Cancel a running job")
  print("  retry <job_id>        Retry a failed job")
  print("  drain <domain_id>     Drain a manager (stop new work)")
  print("  undrain <domain_id>   Resume a drained manager")
  print("  forget <domain_id>    Remove an offline manager")
  print("  watch                 Live dashboard")
  print("  config [set k v]      View or edit config")
  print("  log [n]               Show recent cluster events")
  print("  pair [start|status|close]")
  print("                        Trust-bootstrap helper for new Managers")
  os.exit(0)
end

local args = {...}
local sub = table.remove(args, 1)
if not sub then usage() end
local fn = SUBCOMMANDS[sub]
if not fn then
  io.stderr:write("unknown subcommand: " .. sub .. "\n")
  usage()
end

local ok, err = pcall(fn, args)
if not ok then
  io.stderr:write("cluster: " .. tostring(err) .. "\n")
  os.exit(1)
end
