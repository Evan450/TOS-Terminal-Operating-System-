-- ╔══════════════════════════════════════════════════════════╗
-- ║  Unit Test: cluster.jobs — assignment lifecycle           ║
-- ║                                                           ║
-- ║  jobs.lua owns everything between "a job was submitted"    ║
-- ║  and "the job is finalized": splitting, dispatch, the      ║
-- ║  retry budget, timeouts, Manager-offline reassignment and  ║
-- ║  multi-chunk result reassembly. It exposed an _internal    ║
-- ║  table for a harness that never got written, so all of     ║
-- ║  that shipped untested.                                    ║
-- ║                                                           ║
-- ║  This is that harness. It drives the REAL jobs.lua against ║
-- ║  the REAL state.lua (uninitialized, so purely in-memory)   ║
-- ║  with a stub net, and pins the behaviour the protocol spec ║
-- ║  asks for: §4.3 assignment shape, §4.4 result/chunk        ║
-- ║  handling, §8.2 per-policy redistribution, §8.6 dedupe by  ║
-- ║  assignment_id accepting whichever result arrives FIRST.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_jobs.lua

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
-- Same approach as test_cluster_storage_pref.lua: stub the module loads
-- so the real files run outside TOS. state.lua only persists once init()
-- has set a path, so leaving it uninitialized keeps everything in RAM
-- and touches no disk.
local _uptime = 0
local function clockAt(t) _uptime = t end

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

local jobs = loadRel("master-skeleton/lib/cluster/jobs.lua")
-- Each call re-runs the chunk, so every scenario gets a virgin store
-- rather than inheriting the previous section's jobs and counters.
local function freshState() return loadRel("master-skeleton/lib/cluster/state.lua") end

if not (jobs and freshState()) then
  print("FAIL: could not load cluster modules (jobs=" .. tostring(jobs ~= nil) .. ")")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- A net stub that records what was sent and can be told to fail.
local function fakeNet()
  local n = { sent = {}, cancels = {}, fail = false, err = "unreachable" }
  function n.sendAssignment(addr, a)
    if n.fail then return false, n.err end
    n.sent[#n.sent + 1] = { addr = addr, assignment_id = a.assignment_id }
    return true
  end
  function n.sendCancel(addr, aid)
    n.cancels[#n.cancels + 1] = { addr = addr, assignment_id = aid }
    return true
  end
  return n
end

local function tasks(n)
  local t = {}
  for i = 1, n do t[i] = { id = i } end
  return t
end

-- Count assignments on a job (they live in a sparse map keyed by id).
local function asnCount(job)
  local c = 0
  for _ in pairs(job.assignments) do c = c + 1 end
  return c
end

-- Assignments sorted by split_index, so slice assertions are stable.
local function asnList(job)
  local out = {}
  for _, a in pairs(job.assignments) do out[#out + 1] = a end
  table.sort(out, function(x, y) return (x.split_index or 0) < (y.split_index or 0) end)
  return out
end

-- Submit a job and split it in one step; returns state, job_id, assignments.
local function submit(st, spec)
  local job_id = st.createJob(spec)
  jobs.splitIntoAssignments(job_id, spec, st)
  return job_id, asnList(st.getJob(job_id))
end

print("=== cluster.jobs Tests ===")
print()

-- ── 1. Retry budgets ──────────────────────────────────────────────
-- §8.2: "safe" redistributes, "once" redistributes once then gives up,
-- "none" is marked failed. The budget is TOTAL attempts, initial
-- dispatch included — so "once" is 2, not 1.
print("-- attemptsFor --")
local attemptsFor = jobs._internal.attemptsFor
test("exposes _internal",        "table",    type(jobs._internal))
test("safe -> 5 attempts",       5,          attemptsFor("safe"))
test("once -> 2 attempts",       2,          attemptsFor("once"))
test("none -> 1 attempt",        1,          attemptsFor("none"))
test("nil defaults to safe",     5,          attemptsFor(nil))
test("unknown policy -> 1",      1,          attemptsFor("wishful"))

-- ── 2. Splitting ──────────────────────────────────────────────────
print()
print("-- splitIntoAssignments --")
local MAXT = jobs._internal.MAX_TASKS_PER_ASSIGNMENT
test("chunk size is 40", 40, MAXT)

do
  local st = freshState()

  -- A zero-task job is legal: it still gets one assignment so the
  -- lifecycle runs (jobs that compute their own inputs Manager-side).
  local _, a0 = submit(st, { tasks = {} })
  test("0 tasks -> 1 assignment",   1, #a0)
  test("...with an empty slice",    0, #a0[1].tasks_inline)

  local _, a1 = submit(st, { tasks = tasks(1) })
  test("1 task -> 1 assignment",    1, #a1)

  -- Everything up to a full chunk collapses to one assignment; the split
  -- only bites past MAX_TASKS_PER_ASSIGNMENT. There is no separate
  -- small-job threshold, and these three pin that there is no seam where
  -- one used to be.
  local _, a8  = submit(st, { tasks = tasks(8) })
  local _, a9  = submit(st, { tasks = tasks(9) })
  local _, a40 = submit(st, { tasks = tasks(40) })
  test("8 tasks -> 1 assignment",   1, #a8)
  test("9 tasks -> 1 assignment",   1, #a9)
  test("40 tasks -> 1 assignment",  1, #a40)

  local _, a41 = submit(st, { tasks = tasks(41) })
  test("41 tasks -> 2 assignments", 2, #a41)
  test("...first slice is full",    40, #a41[1].tasks_inline)
  test("...second slice is 1",      1,  #a41[2].tasks_inline)

  local _, a80 = submit(st, { tasks = tasks(80) })
  test("80 tasks -> 2 assignments", 2, #a80)
  test("...no empty tail slice",    40, #a80[2].tasks_inline)

  local _, a81 = submit(st, { tasks = tasks(81) })
  test("81 tasks -> 3 assignments", 3, #a81)

  -- split_index is 1-based and contiguous — it's what the operator sees
  -- in `cluster jobs <id>` and what log lines key on.
  test("split_index starts at 1",   1, a81[1].split_index)
  test("split_index is contiguous", 2, a81[2].split_index)
  test("...through the tail",       3, a81[3].split_index)

  -- Every task must land in exactly one slice, in order. A chunking bug
  -- that drops or duplicates work is silent otherwise: the job still
  -- "completes", just with a hole in it.
  local seen, dupes, order_ok = {}, 0, true
  local expect_next = 1
  for _, a in ipairs(a81) do
    for _, t in ipairs(a.tasks_inline) do
      if seen[t.id] then dupes = dupes + 1 end
      seen[t.id] = true
      if t.id ~= expect_next then order_ok = false end
      expect_next = expect_next + 1
    end
  end
  local missing = 0
  for i = 1, 81 do if not seen[i] then missing = missing + 1 end end
  test("no task lost across slices",      0,    missing)
  test("no task duplicated",              0,    dupes)
  test("task order preserved end to end", true, order_ok)

  -- state.createJob keeps `spec` for retry, so an assignment must never
  -- share a table with it. The small-job branch that used to live here
  -- passed the caller's own `tasks` through, which meant the tasks_ref
  -- swap would have hollowed out the spec the retry path depends on.
  local spec = { tasks = tasks(3) }
  local jid = st.createJob(spec)
  jobs.splitIntoAssignments(jid, spec, st)
  local mine = asnList(st.getJob(jid))[1]
  test("slice is not the caller's table", false, mine.tasks_inline == spec.tasks)
  test("...but has the same contents",    3,     #mine.tasks_inline)
  mine.tasks_inline = nil                       -- stand in for the tasks_ref swap
  test("...so the retry spec survives",   3,     #st.getJob(jid).spec.tasks)
end

-- ── 3. Assignment shape (§4.3) ────────────────────────────────────
print()
print("-- assignment fields --")
do
  local st = freshState()
  local spec = {
    tasks = tasks(2), priority = 9, deadline = 1700, retry_policy = "once",
    compute_profile = "compute_bound", storage_preference = "raid",
    result_sink = "inline", inputs = { seed = 7 },
  }
  local _, a = submit(st, spec)
  local one = a[1]
  test("carries priority",           9,               one.priority)
  test("carries deadline",           1700,            one.deadline)
  test("carries retry_policy",       "once",          one.retry_policy)
  test("carries compute_profile",    "compute_bound", one.compute_profile)
  test("carries storage_preference", "raid",          one.storage_preference)
  test("carries inputs_inline",      7,               one.inputs_inline.seed)
  test("starts pending",             "pending",       one.state)
  test("starts at 0 attempts",       0,               one.attempts)
  -- max_attempts is stamped at split time; the retry paths recompute the
  -- budget from job.retry_policy. The two must agree or the field lies.
  test("max_attempts matches policy", attemptsFor("once"), one.max_attempts)
  test("inline sink has no prefix",  nil,             one.result_prefix)

  local _, b = submit(st, { tasks = tasks(1), result_sink = "public" })
  test("public sink gets a prefix", "public://job-2/results/", b[1].result_prefix)

  -- Defaults, for a spec that says nothing.
  local _, c = submit(st, { tasks = tasks(1) })
  test("default priority 5",       5,        c[1].priority)
  test("default deadline 0",       0,        c[1].deadline)
  test("default policy safe",      "safe",   c[1].retry_policy)
  test("default profile mixed",    "mixed",  c[1].compute_profile)
  test("default sink inline",      "inline", c[1].result_sink)
end

-- ── 4. The pending queue ──────────────────────────────────────────
print()
print("-- pendingAssignments --")
do
  local st = freshState()
  -- Same priority, different deadlines; then a high-priority job that
  -- must jump the queue regardless of deadline.
  local jLate  = select(1, submit(st, { tasks = tasks(1), deadline = 900 }))
  local jSoon  = select(1, submit(st, { tasks = tasks(1), deadline = 100 }))
  local jNone  = select(1, submit(st, { tasks = tasks(1), deadline = 0 }))
  local jUrgent= select(1, submit(st, { tasks = tasks(1), priority = 9 }))

  local q = jobs.pendingAssignments(st)
  test("all four queued",           4,       #q)
  test("priority wins first",       jUrgent, q[1].job_id)
  test("then earliest deadline",    jSoon,   q[2].job_id)
  test("then later deadline",       jLate,   q[3].job_id)
  test("deadline 0 sorts last",     jNone,   q[4].job_id)

  -- A terminal job's leftovers must never be handed back to the
  -- scheduler, or a cancelled job quietly keeps consuming domains.
  st.setJobState(jNone, "cancelled")
  local q2 = jobs.pendingAssignments(st)
  test("terminal job is skipped",   3,       #q2)
end

-- ── 5. Dispatch ───────────────────────────────────────────────────
print()
print("-- dispatch --")
do
  local st, net = freshState(), fakeNet()
  clockAt(50)
  local job_id, a = submit(st, { tasks = tasks(1) })
  local one = a[1]

  local ok = jobs.dispatch(one, "addr-mgr", st, net)
  test("dispatch reports ok",        true,       ok)
  test("assignment is running",      "running",  one.state)
  test("records the assignee",       "addr-mgr", one.assigned_to)
  test("stamps dispatched_at",       50,         one.dispatched_at)
  test("burns one attempt",          1,          one.attempts)
  test("sent exactly one packet",    1,          #net.sent)
  test("...to the right Manager",    "addr-mgr", net.sent[1].addr)
  test("parent job goes running",    "running",  st.getJob(job_id).state)
  test("...and is no longer pending", 0,         #jobs.pendingAssignments(st))
end

do
  -- A send that fails must leave nothing half-dispatched: the assignment
  -- returns to the queue for a different domain next tick.
  local st, net = freshState(), fakeNet()
  net.fail = true
  local _, a = submit(st, { tasks = tasks(1) })
  local one = a[1]

  local ok, err = jobs.dispatch(one, "addr-dead", st, net)
  test("failed send reports false",   false,                    ok)
  -- Coded per error-conventions.md §4/§5: a stable prefix the caller can
  -- classify on, with the transport's own words preserved behind it.
  test("...surfaces a coded reason",  "send_failed: unreachable", err)
  test("...code is greppable",        "send_failed",            err:match("^[%a_][%w_]*"))
  test("...requeues as pending",      "pending",     one.state)
  test("...clears the assignee",      nil,           one.assigned_to)
  test("...and is queued again",      1,             #jobs.pendingAssignments(st))
  -- A send that never left the Master is not an attempt at running the
  -- work; charging it to the retry budget spends the job's redistribution
  -- allowance on an unreachable Manager (§8.2).
  test("...does not burn an attempt", 0,             one.attempts)
end

-- ── 6. Results (§4.4) ─────────────────────────────────────────────
print()
print("-- onResult --")
do
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1) })
  jobs.dispatch(a[1], "addr-mgr", st, net)
  clockAt(120)
  local ok = jobs.onResult(a[1].assignment_id, {
    status = "ok", output_inline = "42",
    stats = { tasks_total = 1, tasks_ok = 1 },
  }, st)
  test("ok result accepted",       true,        ok)
  test("assignment completed",     "completed", a[1].state)
  test("stamps completed_at",      120,         a[1].completed_at)
  test("keeps the output",         "42",        a[1].result.output_inline)
  test("keeps the stats",          1,           a[1].result.stats.tasks_ok)
  test("job finalizes as done",    "done",      st.getJob(job_id).state)
end

do
  -- "partial" is still done: the per-task failures ride in result.errors
  -- rather than sinking the whole assignment.
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1) })
  jobs.dispatch(a[1], "addr-mgr", st, net)
  jobs.onResult(a[1].assignment_id, { status = "partial", errors = { "task 3" } }, st)
  test("partial completes",        "completed", a[1].state)
  test("...keeps errors",          "task 3",    a[1].result.errors[1])
  test("...job still done",        "done",      st.getJob(job_id).state)
end

do
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1) })
  jobs.dispatch(a[1], "addr-mgr", st, net)
  jobs.onResult(a[1].assignment_id, { status = "cancelled" }, st)
  test("cancelled propagates",     "cancelled", a[1].state)
  test("...job reads cancelled",   "cancelled", st.getJob(job_id).state)
end

do
  local st = freshState()
  local ok, err = jobs.onResult(9999, { status = "ok" }, st)
  test("unknown assignment refused", false,                ok)
  test("...with a reason",           "no_such_assignment", err)
end

-- ── 7. Retry budget on failed results (§8.2) ──────────────────────
print()
print("-- retry policy --")
do
  -- "safe": 5 total attempts. Each failure requeues until the budget is
  -- spent, then the assignment sticks and the job fails.
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1), retry_policy = "safe" })
  local one = a[1]
  local requeues = 0
  for _ = 1, 5 do
    jobs.dispatch(one, "addr-mgr", st, net)
    jobs.onResult(one.assignment_id, { status = "failed" }, st)
    if one.state == "pending" then requeues = requeues + 1 end
  end
  test("safe requeues 4 times",      4,        requeues)
  test("...then stays failed",       "failed", one.state)
  test("...having spent 5 attempts", 5,        one.attempts)
  test("...job finalizes failed",    "failed", st.getJob(job_id).state)
end

do
  -- "once": redistributed exactly once.
  local st, net = freshState(), fakeNet()
  local _, a = submit(st, { tasks = tasks(1), retry_policy = "once" })
  local one = a[1]
  jobs.dispatch(one, "addr-mgr", st, net)
  jobs.onResult(one.assignment_id, { status = "failed" }, st)
  test("once requeues on 1st fail", "pending", one.state)
  test("...tagged with the reason", "failed_result", one.retry_reason)
  jobs.dispatch(one, "addr-other", st, net)
  jobs.onResult(one.assignment_id, { status = "failed" }, st)
  test("...gives up on 2nd fail",   "failed",  one.state)
  test("...having tried twice",     2,         one.attempts)
end

do
  -- "none": no redistribution at all, ever.
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1), retry_policy = "none" })
  local one = a[1]
  jobs.dispatch(one, "addr-mgr", st, net)
  jobs.onResult(one.assignment_id, { status = "failed" }, st)
  test("none never requeues",     "failed", one.state)
  test("...one attempt only",     1,        one.attempts)
  test("...job fails immediately","failed", st.getJob(job_id).state)
end

-- ── 8. Duplicate results (§8.6) ───────────────────────────────────
-- "Master should dedupe by assignment_id and accept whichever result
-- arrives first." A healed partition delivers two results for the same
-- assignment; the second must not be able to rewrite a settled one.
print()
print("-- duplicate / late results --")
do
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1), retry_policy = "safe" })
  local one = a[1]
  jobs.dispatch(one, "addr-mgr", st, net)
  jobs.onResult(one.assignment_id, { status = "ok", output_inline = "first" }, st)
  test("first result settles it",  "completed", one.state)
  test("job is done",              "done",      st.getJob(job_id).state)

  -- The straggler from the other side of the partition.
  jobs.onResult(one.assignment_id, { status = "failed", output_inline = "second" }, st)
  test("late failure ignored",     "completed", one.state)
  test("...output not overwritten","first",     one.result.output_inline)
  test("...job stays done",        "done",      st.getJob(job_id).state)
  -- The sharp edge: rewriting a completed assignment to "failed" runs it
  -- through the retry path, which parks it back in "pending" inside a job
  -- the scheduler no longer looks at — work that can never be dispatched
  -- and a job that can never be re-finalized.
  test("...not resurrected as pending", false, one.state == "pending")
end

do
  -- A duplicate "ok" is just as much a rewrite, and it re-stamps
  -- completed_at, so the operator's timing data drifts on every replay.
  local st, net = freshState(), fakeNet()
  local _, a = submit(st, { tasks = tasks(1) })
  jobs.dispatch(a[1], "addr-mgr", st, net)
  clockAt(200)
  jobs.onResult(a[1].assignment_id, { status = "ok", output_inline = "first" }, st)
  clockAt(900)
  jobs.onResult(a[1].assignment_id, { status = "ok", output_inline = "replay" }, st)
  test("duplicate ok keeps output",   "first", a[1].result.output_inline)
  test("...keeps original timestamp", 200,     a[1].completed_at)
end

-- ── 9. Timeouts ───────────────────────────────────────────────────
print()
print("-- onAssignmentTimeout --")
do
  local st, net = freshState(), fakeNet()
  local _, a = submit(st, { tasks = tasks(1), retry_policy = "safe" })
  local one = a[1]
  jobs.dispatch(one, "addr-mgr", st, net)

  local ok = jobs.onAssignmentTimeout(one.assignment_id, st, net)
  test("timeout handled",             true,                 ok)
  test("requeued within budget",      "pending",            one.state)
  test("...reason recorded",          "deadline_exceeded",  one.retry_reason)
  test("...assignee cleared",         nil,                  one.assigned_to)
  -- Best-effort: tell the Manager to stop working on it, so a domain
  -- doesn't grind on an assignment that's already been handed elsewhere.
  test("...cancel sent to Manager",   1,                    #net.cancels)
  test("...for the right assignment", one.assignment_id,    net.cancels[1].assignment_id)

  -- A timeout for something not running is a no-op, not a state change.
  local again = jobs.onAssignmentTimeout(one.assignment_id, st, net)
  test("timeout on pending is a no-op", false, again)
  test("...state untouched",            "pending", one.state)
end

do
  -- Budget exhausted: the timeout is terminal and the job finalizes.
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1), retry_policy = "once" })
  local one = a[1]
  jobs.dispatch(one, "addr-mgr", st, net)
  jobs.onAssignmentTimeout(one.assignment_id, st, net)
  jobs.dispatch(one, "addr-other", st, net)
  clockAt(400)
  jobs.onAssignmentTimeout(one.assignment_id, st, net)
  test("exhausted timeout fails",   "failed",            one.state)
  test("...records the reason",     "deadline_exceeded", one.reason)
  test("...stamps completed_at",    400,                 one.completed_at)
  test("...finalizes the job",      "failed",            st.getJob(job_id).state)
end

do
  -- retry_policy "none" gets no second chance on a timeout either.
  local st, net = freshState(), fakeNet()
  local _, a = submit(st, { tasks = tasks(1), retry_policy = "none" })
  jobs.dispatch(a[1], "addr-mgr", st, net)
  jobs.onAssignmentTimeout(a[1].assignment_id, st, net)
  test("none fails on first timeout", "failed", a[1].state)
end

-- ── 10. Manager offline (§8.2) ────────────────────────────────────
print()
print("-- onManagerOffline --")
do
  local st, net = freshState(), fakeNet()
  local DEAD, LIVE = "addr-dead", "addr-live"
  local dead_domain = st.registerManager(DEAD, { hostname = "mgr-dead" })
  st.registerManager(LIVE, { hostname = "mgr-live" })

  local jSafe, aSafe = submit(st, { tasks = tasks(1), retry_policy = "safe" })
  local jNone, aNone = submit(st, { tasks = tasks(1), retry_policy = "none" })
  local jElse, aElse = submit(st, { tasks = tasks(1), retry_policy = "safe" })
  jobs.dispatch(aSafe[1], DEAD, st, net)
  jobs.dispatch(aNone[1], DEAD, st, net)
  jobs.dispatch(aElse[1], LIVE, st, net)

  clockAt(500)
  jobs.onManagerOffline(dead_domain, st)
  test("safe work is redistributed", "pending",          aSafe[1].state)
  test("...reason recorded",         "manager_offline",  aSafe[1].retry_reason)
  test("...assignee cleared",        nil,                aSafe[1].assigned_to)
  test("...job still running",       "running",          st.getJob(jSafe).state)

  test("none-policy work is lost",   "lost",             aNone[1].state)
  test("...reason recorded",         "manager_offline",  aNone[1].reason)
  test("...job finalizes failed",    "failed",           st.getJob(jNone).state)

  -- Work on a healthy Manager must not be touched. This is the one that
  -- turns a single domain's outage into a cluster-wide stampede if wrong.
  test("other domains untouched",    "running",          aElse[1].state)
  test("...still assigned",          LIVE,               aElse[1].assigned_to)
  test("...its job still running",   "running",          st.getJob(jElse).state)
end

do
  -- An unknown domain_id is a no-op, not an error and not a mass requeue.
  local st, net = freshState(), fakeNet()
  local _, a = submit(st, { tasks = tasks(1) })
  jobs.dispatch(a[1], "addr-mgr", st, net)
  jobs.onManagerOffline(404, st)
  test("unknown domain leaves work alone", "running", a[1].state)
end

-- ── 11. Chunked results (§4.4) ────────────────────────────────────
print()
print("-- onResultChunk --")
do
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(1) })
  local aid = a[1].assignment_id
  jobs.dispatch(a[1], "addr-mgr", st, net)

  local ok, why = jobs.onResultChunk(aid, 1, 3, "alpha-", nil, st)
  test("partial set is incomplete", false,        ok)
  test("...says so",                "incomplete", why)
  test("...assignment still running", "running",  a[1].state)

  -- Chunks arrive out of order; reassembly must go by chunk_idx, not by
  -- arrival, or the blob is silently scrambled.
  jobs.onResultChunk(aid, 3, 3, "omega", { tasks_ok = 1 }, st)
  test("still incomplete with a hole", false, jobs.onResultChunk(aid, 3, 3, "omega", nil, st))

  local done = jobs.onResultChunk(aid, 2, 3, "beta-", nil, st)
  test("last chunk completes it",   true,               done)
  test("reassembled in index order","alpha-beta-omega", a[1].result.output_inline)
  test("...carries final_stats",    1,                  a[1].result.stats.tasks_ok)
  test("...assignment completed",   "completed",        a[1].state)
  test("...job finalized",          "done",             st.getJob(job_id).state)
  test("...buffer released",        nil,                jobs._internal.chunkBuffer[aid])
end

do
  -- A Manager that dies mid-transfer leaves a partial buffer behind.
  -- It must be swept, or the Master leaks memory it does not have.
  local st, net = freshState(), fakeNet()
  local _, a = submit(st, { tasks = tasks(1) })
  local aid = a[1].assignment_id
  jobs.dispatch(a[1], "addr-mgr", st, net)

  clockAt(1000)
  jobs.onResultChunk(aid, 1, 4, "orphan", nil, st)
  test("buffer holds the fragment", "table", type(jobs._internal.chunkBuffer[aid]))

  -- Well past the 300 s stale window; the next chunk for anyone sweeps it.
  clockAt(1400)
  local _, b = submit(st, { tasks = tasks(1) })
  jobs.onResultChunk(b[1].assignment_id, 1, 2, "x", nil, st)
  test("stale buffer swept",        nil,     jobs._internal.chunkBuffer[aid])
  test("...fresh one survives",     "table", type(jobs._internal.chunkBuffer[b[1].assignment_id]))
end

-- ── 12. Finalization ──────────────────────────────────────────────
print()
print("-- finalizeJob --")
do
  local st, net = freshState(), fakeNet()
  -- A multi-assignment job stays running until the LAST one lands.
  local job_id, a = submit(st, { tasks = tasks(81) })
  test("81 tasks -> 3 assignments", 3, #a)
  for _, one in ipairs(a) do jobs.dispatch(one, "addr-mgr", st, net) end

  jobs.onResult(a[1].assignment_id, { status = "ok" }, st)
  test("1 of 3 done: still running", "running", st.getJob(job_id).state)
  jobs.onResult(a[2].assignment_id, { status = "ok" }, st)
  test("2 of 3 done: still running", "running", st.getJob(job_id).state)
  jobs.onResult(a[3].assignment_id, { status = "ok" }, st)
  test("3 of 3 done: finalized",     "done",    st.getJob(job_id).state)
end

do
  local st = freshState()
  local ok, err = jobs.finalizeJob(4242, st)
  test("finalizing an unknown job fails", false,        ok)
  test("...with a reason",                "no_such_job", err)
end

do
  -- Mixed outcome under a retry policy that allowed retries: partial
  -- success is reported as "done", not "failed" — the completed slices
  -- produced real output and the operator can retry the job.
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(41), retry_policy = "once" })
  test("41 tasks -> 2 assignments", 2, #a)
  jobs.dispatch(a[1], "addr-mgr", st, net)
  jobs.dispatch(a[2], "addr-mgr", st, net)
  jobs.onResult(a[1].assignment_id, { status = "ok" }, st)
  -- Burn the second slice's whole budget.
  jobs.onResult(a[2].assignment_id, { status = "failed" }, st)
  jobs.dispatch(a[2], "addr-other", st, net)
  jobs.onResult(a[2].assignment_id, { status = "failed" }, st)
  test("second slice exhausted",   "failed", a[2].state)
  test("mixed outcome reads done", "done",   st.getJob(job_id).state)
end

do
  -- Every slice cancelled and nothing else: the job is cancelled, not failed.
  local st, net = freshState(), fakeNet()
  local job_id, a = submit(st, { tasks = tasks(41) })
  jobs.dispatch(a[1], "addr-mgr", st, net)
  jobs.dispatch(a[2], "addr-mgr", st, net)
  jobs.onResult(a[1].assignment_id, { status = "cancelled" }, st)
  jobs.onResult(a[2].assignment_id, { status = "cancelled" }, st)
  test("all-cancelled job is cancelled", "cancelled", st.getJob(job_id).state)
end

-- ── 13. The CLEAR sentinel ────────────────────────────────────────
-- Every requeue path above depends on this. `{ assigned_to = nil }` is
-- an empty table in Lua, so the pairs() walk in setAssignmentState never
-- sees the key and the stale value survives — which is exactly how five
-- separate call sites all failed to clear the assignee.
print()
print("-- state.CLEAR --")
do
  local st = freshState()
  local _, a = submit(st, { tasks = tasks(1) })
  local one = a[1]
  test("state exports CLEAR", true, st.CLEAR ~= nil)

  st.setAssignmentState(one.job_id, one.assignment_id, "running",
    { assigned_to = "addr-mgr", note = "keep me" })
  test("plain value is set",   "addr-mgr", one.assigned_to)

  -- The trap, pinned: a literal nil is indistinguishable from absence.
  st.setAssignmentState(one.job_id, one.assignment_id, "pending", { assigned_to = nil })
  test("nil cannot clear a field", "addr-mgr", one.assigned_to)

  st.setAssignmentState(one.job_id, one.assignment_id, "pending",
    { assigned_to = st.CLEAR })
  test("CLEAR removes the field",  nil,       one.assigned_to)
  test("...and nothing else",      "keep me", one.note)
  test("...state still applied",   "pending", one.state)
end

-- ── 14. allAssignmentsTerminal ────────────────────────────────────
print()
print("-- allAssignmentsTerminal --")
do
  local terminal = jobs._internal.allAssignmentsTerminal
  test("nil job is not terminal", false, terminal(nil))
  test("no assignments -> terminal", true, terminal({ assignments = {} }))
  test("pending blocks",   false, terminal({ assignments = { [1] = { state = "pending" } } }))
  test("running blocks",   false, terminal({ assignments = { [1] = { state = "running" } } }))
  test("completed passes", true,  terminal({ assignments = { [1] = { state = "completed" } } }))
  test("failed passes",    true,  terminal({ assignments = { [1] = { state = "failed" } } }))
  test("lost passes",      true,  terminal({ assignments = { [1] = { state = "lost" } } }))
  test("cancelled passes", true,  terminal({ assignments = { [1] = { state = "cancelled" } } }))
  test("one live blocks the set", false, terminal({ assignments = {
    [1] = { state = "completed" }, [2] = { state = "running" } } }))
end

-- ── 15. Error-code conformance ────────────────────────────────────
-- error-conventions.md §4: `err` is a stable snake_case code, optionally
-- followed by ": " and human detail. This section is the enforcement —
-- without it the convention is a document that drifts away from the code
-- one well-meaning reword at a time.
--
-- Only reaches state.lua and jobs.lua; api.lua's strings were migrated in
-- the same pass but need a bound daemon to exercise, so they are checked
-- by inspection in that document's §7, not here.
print()
print("-- error-code conformance --")
do
  local function isCoded(err)
    if type(err) ~= "string" then return false end
    return err:match("^[a-z][a-z0-9_]*$") ~= nil
        or err:match("^[a-z][a-z0-9_]*: .") ~= nil
  end
  -- The shape check itself must be able to fail, or it proves nothing.
  test("rejects prose",        false, isCoded("no such job"))
  test("rejects capitals",     false, isCoded("No_Such_Job"))
  test("rejects a bare colon", false, isCoded("no_such_job: "))
  test("accepts a bare code",  true,  isCoded("no_such_job"))
  test("accepts code+detail",  true,  isCoded("send_failed: unreachable"))

  local st, net = freshState(), fakeNet()
  net.fail = true
  local job_id, a = submit(st, { tasks = tasks(1) })
  local one = a[1]
  local BAD_JOB, BAD_ASN = 4242, 9999

  -- Each row: label, and the err actually returned by a real failure.
  local function errOf(...) local _, e = ... ; return e end
  local cases = {
    { "state.setAssignmentState/no job",
      errOf(st.setAssignmentState(BAD_JOB, one.assignment_id, "pending")) },
    { "state.setAssignmentState/no asn",
      errOf(st.setAssignmentState(job_id, BAD_ASN, "pending")) },
    { "state.setJobState",       errOf(st.setJobState(BAD_JOB, "done")) },
    { "state.setManagerState/bad state",
      errOf(st.setManagerState("addr-x", "bogus")) },
    { "state.setManagerState/unknown",
      errOf(st.setManagerState("addr-x", "active")) },
    { "state.forgetManager",     errOf(st.forgetManager("addr-x")) },
    { "state.updateManagerHeartbeat", errOf(st.updateManagerHeartbeat("addr-x", {})) },
    { "state.addAssignment",     errOf(st.addAssignment(BAD_JOB, {})) },
    { "state.load/no path",      errOf(st.load()) },
    { "state.save/no path",      errOf(st.save()) },
    { "jobs.onResult/unknown",   errOf(jobs.onResult(BAD_ASN, { status = "ok" }, st)) },
    { "jobs.finalizeJob",        errOf(jobs.finalizeJob(BAD_JOB, st)) },
    { "jobs.dispatch/send fail", errOf(jobs.dispatch(one, "addr-dead", st, net)) },
    { "jobs.onResultChunk/partial",
      errOf(jobs.onResultChunk(one.assignment_id, 1, 3, "x", nil, st)) },
    { "jobs.onAssignmentTimeout/not running",
      errOf(jobs.onAssignmentTimeout(one.assignment_id, st, net)) },
  }
  for _, c in ipairs(cases) do
    test(c[1] .. " -> coded", true, isCoded(c[2]))
  end

  -- And the duplicate-result path, which needs a settled assignment.
  net.fail = false
  local st2, net2 = freshState(), fakeNet()
  local _, b = submit(st2, { tasks = tasks(1) })
  jobs.dispatch(b[1], "addr-mgr", st2, net2)
  jobs.onResult(b[1].assignment_id, { status = "ok" }, st2)
  local _, dupErr = jobs.onResult(b[1].assignment_id, { status = "ok" }, st2)
  test("jobs.onResult/duplicate -> coded", true,               isCoded(dupErr))
  test("...and is the canonical code",     "duplicate_result", dupErr)

  -- §2: a lookup that finds nothing has succeeded. These must stay
  -- bare nil, with no error string invented for them.
  test("getJob absence has no error",     nil, errOf(st.getJob(BAD_JOB)))
  test("getManager absence has no error", nil, errOf(st.getManager("addr-x")))
end

-- ── 16. Public storage: pointers instead of payloads ───────────
-- §4.3 gives an assignment two ways to carry its work: tasks_inline, or
-- tasks_ref pointing into Public storage. Design principle 5 says the
-- 6 KB packet ceiling is never routed around with heroic chunking when a
-- scratch tier exists. These pin BOTH halves -- that a big slice becomes
-- a pointer when a Storage Node is there, and that nothing changes at
-- all when one is not.
print()
print("-- public storage spill --")
do
  local ser = { encode = function(t)
    -- Size stands in for real serialization: one entry per task.
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return string.rep("x", n * 200)
  end }

  local function fakeStore(opts)
    opts = opts or {}
    local st = { puts = {}, releases = {}, addr = opts.addr }
    function st.available() return st.addr ~= nil end
    function st.address() return st.addr end
    function st.tasksKey(job_id, idx)
      return string.format("job-%d/tasks/assignment-%d", job_id, idx)
    end
    function st.put(key, blob)
      if opts.failPut then return nil, "out_of_space: disk is full" end
      st.puts[#st.puts + 1] = { key = key, bytes = #blob }
      return { key = key, lease_id = "LEASE-" .. #st.puts, size_bytes = #blob }
    end
    function st.release(key, lease)
      st.releases[#st.releases + 1] = { key = key, lease = lease }
      return { key = key, released = true }
    end
    return st
  end

  -- (a) No Storage Node: everything stays inline, exactly as before.
  do
    local store = fakeStore({ addr = nil })
    jobs.setStore(store, ser)
    local st2 = freshState()
    local _, a = submit(st2, { tasks = tasks(40) })     -- 8000 "bytes"
    test("no node: slice stays inline",    "table", type(a[1].tasks_inline))
    test("no node: no ref is set",         nil,     a[1].tasks_ref)
    test("no node: nothing was written",   0,       #store.puts)
  end

  -- (b) Node present, slice under budget: still inline. A pointer costs a
  -- round trip on the worker side, so small work must not pay for it.
  do
    local store = fakeStore({ addr = "addr-store" })
    jobs.setStore(store, ser)
    local st2 = freshState()
    local _, a = submit(st2, { tasks = tasks(10) })     -- 2000 < 4096
    test("small slice stays inline",   "table", type(a[1].tasks_inline))
    test("...no ref",                  nil,     a[1].tasks_ref)
    test("...and no write happened",   0,       #store.puts)
  end

  -- (c) Node present, slice over budget: becomes a pointer.
  do
    local store = fakeStore({ addr = "addr-store" })
    jobs.setStore(store, ser)
    local st2 = freshState()
    local job_id, a = submit(st2, { tasks = tasks(40) })  -- 8000 > 4096
    test("big slice spills",            nil,     a[1].tasks_inline)
    test("...ref names the job key",
      "public://job-" .. job_id .. "/tasks/assignment-1", a[1].tasks_ref)
    test("...lease is kept for release", "LEASE-1", a[1].tasks_lease)
    test("...exactly one write",         1,       #store.puts)
    test("...of the whole slice",        8000,    store.puts[1].bytes)
    -- §4.6: task lists go under job-<id>/, NOT domain-<id>/, so they
    -- outlive the Manager that was working on them.
    test("...under the job namespace", true,
      store.puts[1].key:find("^job%-%d+/") ~= nil)
  end

  -- (d) The node refuses the write. A scratch tier that is full or
  -- unreachable must degrade to a bigger packet, never to a failed job.
  do
    local store = fakeStore({ addr = "addr-store", failPut = true })
    jobs.setStore(store, ser)
    local st2 = freshState()
    local _, a = submit(st2, { tasks = tasks(40) })
    test("failed write falls back to inline", "table", type(a[1].tasks_inline))
    test("...with the tasks intact",          40,      #a[1].tasks_inline)
    test("...and no dangling ref",            nil,     a[1].tasks_ref)
    test("...the job still has its work",     1,       #a)
  end

  -- (e) finalizeJob releases the keys. This is the signal §5.1's
  -- eviction tier 2 needs and a Storage Node cannot generate itself.
  do
    local store, net = fakeStore({ addr = "addr-store" }), fakeNet()
    jobs.setStore(store, ser)
    local st2 = freshState()
    -- 80 tasks = two FULL slices. 41 would give 40 + 1, and the tail of
    -- one task is 200 bytes -- correctly under budget and correctly left
    -- inline, which is a different case (and one (b) already covers).
    local job_id, a = submit(st2, { tasks = tasks(80) })
    test("two full slices, both spilled", 2, #store.puts)
    for _, one in ipairs(a) do jobs.dispatch(one, "addr-mgr", st2, net) end
    for _, one in ipairs(a) do
      jobs.onResult(one.assignment_id, { status = "ok" }, st2)
    end
    test("job finalized",             "done", st2.getJob(job_id).state)
    test("...both keys released",     2,      #store.releases)
    test("...with their own leases",  true,
      store.releases[1].lease ~= store.releases[2].lease)
    test("...naming the job keys",    true,
      store.releases[1].key:find("^job%-" .. job_id .. "/") ~= nil)
  end

  -- (f) A release that throws must not stop the job finalizing. The key
  -- expires on its own TTL anyway; the job outcome is what matters.
  do
    local store = fakeStore({ addr = "addr-store" })
    store.release = function() error("storage node exploded") end
    jobs.setStore(store, ser)
    local st2, net = freshState(), fakeNet()
    local job_id, a = submit(st2, { tasks = tasks(40) })
    jobs.dispatch(a[1], "addr-mgr", st2, net)
    jobs.onResult(a[1].assignment_id, { status = "ok" }, st2)
    test("a throwing release does not block finalize", "done",
      st2.getJob(job_id).state)
  end

  jobs.setStore(nil, nil)   -- leave the module as we found it
  local st3 = freshState()
  local _, a3 = submit(st3, { tasks = tasks(40) })
  test("store detached: back to inline", "table", type(a3[1].tasks_inline))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
