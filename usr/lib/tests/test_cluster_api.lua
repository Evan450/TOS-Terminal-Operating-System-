-- ╔══════════════════════════════════════════════════════════╗
-- ║  Unit Test: cluster.api — the CLI↔daemon contract          ║
-- ║                                                           ║
-- ║  api.lua is the ONLY entrypoint the CLI uses, and it is    ║
-- ║  the surface a future ai-exec dispatches verbs against.    ║
-- ║  That makes its return values an API in the strict sense:  ║
-- ║  error-conventions.md §4 says every failure reason is a     ║
-- ║  stable snake_case code, and until this file existed that   ║
-- ║  was verified by reading rather than by running.            ║
-- ║                                                           ║
-- ║  Drives the real api.lua bound to the real state/scheduler/ ║
-- ║  jobs modules, with a stub net and a stub clusterd.         ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_api.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- ── Off-box stubs ─────────────────────────────────────────────────
local _uptime = 0
package.loaded["filesystem"]  = { exists = function() return false end }
package.loaded["kernel.fs"]   = package.loaded["filesystem"]
package.loaded["computer"]    = { uptime = function() return _uptime end }
package.loaded["event"]       = { on = function() end, interval = function() end,
  timer = function() end, cancelTimer = function() end, pull = function() end }
package.loaded["kernel.event"] = package.loaded["event"]
package.loaded["kernel.serialize"] = {
  serialize = function() return "" end, unserialize = function() return nil end,
  encode = function() return "" end, decode = function() return nil end,
}
package.loaded["kernel.log"] = { info = function() end, warn = function() end,
  error = function() end }
package.loaded["log"] = package.loaded["kernel.log"]

-- api.cancelJob resolves cluster.net lazily through package.loaded.
local _sentCancels = {}
package.loaded["cluster.net"] = {
  sendCancel = function(addr, aid) _sentCancels[#_sentCancels + 1] = { addr, aid } end,
  sendAssignment = function() return true end,
  sendDrain = function() return true end,
}

local function loadFirst(...)
  for _, p in ipairs({ ... }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local BASE = { "../TOS-Extras/cluster/", "TOS-Extras/cluster/" }
local function loadRel(rel)
  local paths = {}
  for _, b in ipairs(BASE) do paths[#paths + 1] = b .. rel end
  return loadFirst(table.unpack(paths))
end

local api       = loadRel("master-skeleton/lib/cluster/api.lua")
local scheduler = loadRel("master-skeleton/lib/cluster/scheduler.lua")
local jobs      = loadRel("master-skeleton/lib/cluster/jobs.lua")
local function freshState() return loadRel("master-skeleton/lib/cluster/state.lua") end

if not (api and scheduler and jobs and freshState()) then
  print("FAIL: could not load cluster modules (api=" .. tostring(api ~= nil)
    .. " scheduler=" .. tostring(scheduler ~= nil)
    .. " jobs=" .. tostring(jobs ~= nil) .. ")")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- A stub daemon. `pairing` controls whether the pairing subsystem is
-- present, which is the difference between a real answer and
-- pairing_unsupported.
local function fakeClusterd(opts)
  opts = opts or {}
  local d = { config = { host_thread_budget = 8, heartbeat_interval = 5 } }
  function d.getConfig() return d.config end
  if opts.pairing ~= false then
    function d.startPairing() return "ABC123", _uptime + 300 end
    function d.closePairing() d.closed = true end
    function d.pairingInfo()
      if opts.window == false then return nil end
      return { expires_in = 300, paired = 0 }
    end
  end
  return d
end

-- Bind a fresh world; returns the state so the test can seed it.
local function bindFresh(opts)
  local st = freshState()
  api.bind(st, scheduler, jobs, fakeClusterd(opts))
  return st
end

-- Give a Manager enough capacity that api.submit's fast-refusal passes.
local function withCapacity(st, addr)
  st.registerManager(addr or "addr-mgr", { hostname = "mgr", worker_count = 4 })
  st.updateManagerHeartbeat(addr or "addr-mgr", {
    state = "active", workers_active = 4, workers_busy = 0,
    queue_depth = 0, storage_used = 0, errors_last_min = 0,
  })
  return st
end

-- error-conventions.md §4.
local function isCoded(err)
  if type(err) ~= "string" then return false end
  return err:match("^[a-z][a-z0-9_]*$") ~= nil
      or err:match("^[a-z][a-z0-9_]*: .") ~= nil
end
local function codeOf(err)
  return type(err) == "string" and err:match("^[%a_][%w_]*") or nil
end

-- Grab the second return value.
local function errOf(...) local _, e = ... ; return e end

print("=== cluster.api Tests ===")
print()

-- ── 1. The bound precondition (§3) ────────────────────────────────
-- Every api call except bind/unbind raises when the daemon isn't
-- running. ai-exec has to pcall regardless of verb, so this is pinned.
print("-- _requireBound raises --")
do
  api.unbind()
  local ok, err = pcall(api.status)
  test("unbound status raises",     false, ok)
  test("...names the daemon",       true,  tostring(err):find("daemon", 1, true) ~= nil)
  test("unbound listJobs raises",   false, pcall(api.listJobs))
  test("unbound submit raises",     false, pcall(api.submit, { tasks = {} }))
  test("unbound cancelJob raises",  false, pcall(api.cancelJob, 1))
  test("unbound drain raises",      false, pcall(api.drainManager, 1))
  -- bind is exempt, or nothing could ever start.
  test("bind itself does not raise", true, pcall(api.bind, freshState(), scheduler,
    jobs, fakeClusterd()))
end

-- ── 2. Job spec validation (§4 codes) ─────────────────────────────
print()
print("-- submit validation --")
do
  local st = withCapacity(bindFresh())
  local cases = {
    { "non-table spec",     "invalid_spec",            errOf(api.submit("nope")) },
    { "non-table tasks",    "invalid_tasks",           errOf(api.submit({ tasks = 7 })) },
    { "bad profile",        "invalid_compute_profile", errOf(api.submit({ compute_profile = "hopeful" })) },
    { "bad retry_policy",   "invalid_retry_policy",    errOf(api.submit({ retry_policy = "wishful" })) },
    { "bad result_sink",    "invalid_result_sink",     errOf(api.submit({ result_sink = "carrier_pigeon" })) },
    { "bad priority",       "invalid_priority",        errOf(api.submit({ priority = 99 })) },
  }
  for _, c in ipairs(cases) do
    test(c[1] .. " -> " .. c[2], c[2], codeOf(c[3]))
    test("..." .. c[1] .. " is coded", true, isCoded(c[3]))
  end
  -- The detail half must survive: it is what the operator reads.
  test("detail carries the bad value", true,
    (errOf(api.submit({ retry_policy = "wishful" })) or ""):find("wishful", 1, true) ~= nil)

  -- A valid spec goes through and returns a job id, not a boolean.
  local job_id, err = api.submit({ tasks = { { id = 1 } }, retry_policy = "safe" })
  test("valid submit returns an id", "number", type(job_id))
  test("...with no error",           nil,      err)
end

do
  -- No capacity anywhere is a refusal, not a crash — and it reuses the
  -- scheduler's own code rather than minting a synonym.
  local st = bindFresh()          -- no managers registered at all
  local id, err = api.submit({ tasks = { { id = 1 } } })
  test("no capacity refuses",        nil,                   id)
  test("...as no_eligible_manager",  "no_eligible_manager",  codeOf(err))
  test("...and is coded",            true,                  isCoded(err))
end

-- ── 3. Lookups: absence vs failure (§2) ───────────────────────────
print()
print("-- absence vs failure --")
do
  local st = withCapacity(bindFresh())
  local job_id = api.submit({ tasks = { { id = 1 } } })

  -- A real job comes back with no error.
  local j, err = api.getJob(job_id)
  test("getJob finds the job",  "number", type(j and j.job_id))
  test("...with no error",      nil,      err)
  test("...and lists assignments", "table", type(j.assignments_list))

  -- A missing job is a coded failure here, matching retryJob. These two
  -- used to disagree: bare nil from one, a reason from the other.
  local missing, mErr = api.getJob(4242)
  test("getJob(missing) -> nil",     nil,           missing)
  test("...coded no_such_job",       "no_such_job", mErr)
  test("retryJob(missing) agrees",   "no_such_job", errOf(api.retryJob(4242)))

  -- A missing argument is a different condition from a missing job.
  test("getJob(nil) -> missing_argument", "missing_argument", codeOf(errOf(api.getJob(nil))))
  test("getManager(nil) -> missing_argument", "missing_argument",
    codeOf(errOf(api.getManager(nil))))

  -- Absence with no error: no Storage Node is configured, and that is a
  -- complete answer rather than a fault.
  local sn, sErr = api.storageStatus()
  test("storageStatus absence -> nil", nil, sn)
  test("...carries no error",          nil, sErr)
end

-- ── 4. Mutating verbs (the agent's §4.2 set) ──────────────────────
print()
print("-- cancel / retry --")
do
  local st = withCapacity(bindFresh())
  local job_id = api.submit({ tasks = { { id = 1 } } })

  test("cancel(nil) -> missing_argument", "missing_argument",
    codeOf(errOf(api.cancelJob(nil))))
  test("cancel(missing) -> no_such_job",  "no_such_job", errOf(api.cancelJob(4242)))

  local ok = api.cancelJob(job_id)
  test("cancel succeeds",        true,        ok)
  test("...job is cancelled",    "cancelled", st.getJob(job_id).state)

  -- Cancelling twice is a wrong_state refusal, not a silent success. An
  -- agent retrying its own cancel must be told nothing happened.
  local ok2, err2 = api.cancelJob(job_id)
  test("double cancel refuses",  false,         ok2)
  test("...as wrong_state",      "wrong_state", codeOf(err2))
  test("...and is coded",        true,          isCoded(err2))

  -- retry only accepts failed jobs; a cancelled one is the wrong state.
  local rid, rErr = api.retryJob(job_id)
  test("retry of cancelled -> nil",  nil,           rid)
  test("...as wrong_state",          "wrong_state", codeOf(rErr))
  test("retry(nil) -> missing_argument", "missing_argument",
    codeOf(errOf(api.retryJob(nil))))
end

do
  -- A failed job can be retried, and retry returns the NEW job id.
  local st = withCapacity(bindFresh())
  local job_id = api.submit({ tasks = { { id = 1 } } })
  st.setJobState(job_id, "failed")
  local new_id, err = api.retryJob(job_id)
  test("retry of failed returns an id", "number", type(new_id))
  test("...a different job",            true,     new_id ~= job_id)
  test("...with no error",              nil,      err)
  test("...and the original is intact", "failed", st.getJob(job_id).state)
end

print()
print("-- drain / undrain / forget --")
do
  local st = withCapacity(bindFresh())
  local dom = st.getManager("addr-mgr").domain_id

  test("drain(nil) -> missing_argument",  "missing_argument",
    codeOf(errOf(api.drainManager(nil))))
  test("drain(missing) -> no_such_domain", "no_such_domain",
    errOf(api.drainManager(999)))

  test("drain succeeds",      true,       api.drainManager(dom))
  test("...manager draining", "draining", st.getManager("addr-mgr").state)
  test("undrain succeeds",    true,       api.undrainManager(dom))
  test("...manager active",   "active",   st.getManager("addr-mgr").state)

  -- Undraining a manager that isn't draining is a wrong_state refusal.
  local ok, err = api.undrainManager(dom)
  test("double undrain refuses", false,         ok)
  test("...as wrong_state",      "wrong_state", codeOf(err))

  -- forget refuses an online manager: destroying registration state for a
  -- live domain is recoverable only by re-pairing, so it is gated on state.
  local fok, fErr = api.forgetManager(dom)
  test("forget of online refuses", false,         fok)
  test("...as wrong_state",        "wrong_state", codeOf(fErr))
  test("...and is coded",          true,          isCoded(fErr))

  st.setManagerState("addr-mgr", "offline")
  test("forget of offline succeeds", true, api.forgetManager(dom))
  test("...manager is gone",         nil,  st.getManager("addr-mgr"))
  test("forget(missing) -> no_such_domain", "no_such_domain",
    errOf(api.forgetManager(999)))
end

-- ── 5. Config (§6 second-slot payload) ────────────────────────────
print()
print("-- config --")
do
  local st = bindFresh()
  test("getConfig returns a table", "table", type(api.getConfig()))
  -- A copy, so a caller can't reach through and mutate the live config.
  local c1 = api.getConfig()
  c1.host_thread_budget = 999
  test("getConfig is a copy", 8, api.getConfig().host_thread_budget)

  test("unknown key -> invalid_key", "invalid_key",
    codeOf(errOf(api.setConfig("nonsense", 1))))
  test("non-numeric -> invalid_value", "invalid_value",
    codeOf(errOf(api.setConfig("host_thread_budget", "abc"))))
  test("non-string -> invalid_value", "invalid_value",
    codeOf(errOf(api.setConfig("storage_node_address", 42))))

  -- Success puts a PAYLOAD in the second slot, which §6 allows because
  -- the first value already answered "did it work".
  local ok, info = api.setConfig("heartbeat_interval", 10)
  test("setConfig succeeds",        true,    ok)
  test("...returns a payload",      "table", type(info))
  test("...flagging restart",       true,    info.restart_required)
  test("...and the value took",     10,      api.getConfig().heartbeat_interval)

  local ok2, info2 = api.setConfig("host_thread_budget", 12)
  test("no-restart key says so", false, info2.restart_required)
end

-- ── 6. Pairing (§6 return shape) ──────────────────────────────────
print()
print("-- pairing --")
do
  local st = bindFresh()
  -- startPairing returns a TABLE. It used to return (code, expires_in),
  -- which put a number in the error slot on success — unreadable by any
  -- caller that had not already checked the outcome.
  local window, err = api.startPairing()
  test("startPairing returns a table", "table",  type(window))
  test("...with no error",             nil,      err)
  test("...carrying the code",         "ABC123", window.code)
  test("...and a numeric expiry",      "number", type(window.expires_in))

  test("pairingInfo returns a table", "table", type(api.pairingInfo()))
  test("closePairing succeeds",       true,    api.closePairing())
end

do
  -- A daemon with no pairing subsystem: all three report the same code
  -- rather than two of them returning a bare false/nil.
  local st = bindFresh({ pairing = false })
  local w, wErr = api.startPairing()
  test("startPairing unsupported -> nil", nil,                   w)
  test("...coded",                        "pairing_unsupported", wErr)
  test("closePairing unsupported",        false,                 api.closePairing())
  test("...coded",                        "pairing_unsupported", errOf(api.closePairing()))
  test("pairingInfo unsupported -> nil",  nil,                   api.pairingInfo())
  test("...coded",                        "pairing_unsupported", errOf(api.pairingInfo()))
end

do
  -- Supported, but no window open. This is absence, and must NOT carry a
  -- reason — otherwise it is indistinguishable from unsupported.
  local st = bindFresh({ window = false })
  local info, err = api.pairingInfo()
  test("no window -> nil",        nil, info)
  test("...with no error",        nil, err)
end

-- ── 7. Readers ────────────────────────────────────────────────────
print()
print("-- status / lists --")
do
  local st = withCapacity(bindFresh())
  api.submit({ tasks = { { id = 1 } } })

  local s = api.status()
  test("status returns a table",     "table", type(s))
  test("...counts an active manager", 1,      s.managers.active)
  test("...counts a pending job",     1,      s.jobs.pending)
  test("...reports thread budget",    8,      s.host_thread_budget)

  test("listManagers returns a list", 1, #api.listManagers())
  test("listJobs returns a list",     1, #api.listJobs())
  test("recentEvents returns a list", "table", type(api.recentEvents(5)))
end

-- ── 8. Every failure reason is coded (§4) ─────────────────────────
-- The sweep. Anything that returns a reason from this module must match
-- the code shape; this is what stops a well-meaning reword from silently
-- becoming an agent-visible behaviour change.
print()
print("-- error-code conformance --")
do
  local st = withCapacity(bindFresh())
  local job_id = api.submit({ tasks = { { id = 1 } } })
  st.setJobState(job_id, "done")

  local cases = {
    { "submit/bad spec",     errOf(api.submit("nope")) },
    { "submit/bad policy",   errOf(api.submit({ retry_policy = "x" })) },
    { "getJob/no arg",       errOf(api.getJob(nil)) },
    { "getJob/missing",      errOf(api.getJob(4242)) },
    { "getManager/no arg",   errOf(api.getManager(nil)) },
    { "cancelJob/no arg",    errOf(api.cancelJob(nil)) },
    { "cancelJob/missing",   errOf(api.cancelJob(4242)) },
    { "cancelJob/terminal",  errOf(api.cancelJob(job_id)) },
    { "retryJob/no arg",     errOf(api.retryJob(nil)) },
    { "retryJob/missing",    errOf(api.retryJob(4242)) },
    { "retryJob/wrong state",errOf(api.retryJob(job_id)) },
    { "drain/no arg",        errOf(api.drainManager(nil)) },
    { "drain/missing",       errOf(api.drainManager(999)) },
    { "undrain/no arg",      errOf(api.undrainManager(nil)) },
    { "undrain/missing",     errOf(api.undrainManager(999)) },
    { "forget/no arg",       errOf(api.forgetManager(nil)) },
    { "forget/missing",      errOf(api.forgetManager(999)) },
    { "setConfig/bad key",   errOf(api.setConfig("nonsense", 1)) },
    { "setConfig/bad value", errOf(api.setConfig("host_thread_budget", "abc")) },
  }
  for _, c in ipairs(cases) do
    test(c[1] .. " -> coded", true, isCoded(c[2]))
  end

  local st2 = bindFresh({ pairing = false })
  test("startPairing/unsupported -> coded", true, isCoded(errOf(api.startPairing())))
  test("closePairing/unsupported -> coded", true, isCoded(errOf(api.closePairing())))
end

api.unbind()

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
