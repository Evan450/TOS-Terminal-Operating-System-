-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the cluster Manager daemon, end to end       ║
-- ║                                                                ║
-- ║  test_cluster_bridge_v2 pins the pure helpers. This drives the ║
-- ║  daemon itself -- start, register, heartbeat, assign, cancel   ║
-- ║  -- through stubbed net/event modules that let the test play   ║
-- ║  the Master and fire the timers by hand. Three findings it     ║
-- ║  exists to pin:                                                ║
-- ║   * a CANCEL that landed between the ASSIGN's ACK and the      ║
-- ║     0.1 s dispatch timer found nothing inflight, reported      ║
-- ║     "cancelled", and then the assignment ran anyway and sent a ║
-- ║     second result;                                             ║
-- ║   * the sender check in onCancel came AFTER the unknown-id     ║
-- ║     branch, so any peer could make the node emit results;      ║
-- ║   * the Master's negotiated heartbeat interval was stored and  ║
-- ║     never read: every Manager heartbeated at the 2 s floor.    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_manager_lifecycle.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

-- ── Stubs: a clock, a net, an event loop the test drives ─────────
local clock = 100
local sent = {}                              -- every net.send
local listeners = {}                         -- type -> { {id, cb}, ... }
local timers = {}                            -- id -> { delay, cb, interval }
local nextId = 0

package.loaded["filesystem"] = { exists = function() return false end }
package.loaded["computer"]   = { uptime = function() return clock end }
package.loaded["event"] = {
  on = function() end,
  interval = function(delay, cb, src) nextId = nextId + 1; timers[nextId] = { delay = delay, cb = cb, interval = true }; return nextId end,
  timer    = function(delay, cb, src) nextId = nextId + 1; timers[nextId] = { delay = delay, cb = cb }; return nextId end,
  cancelTimer = function(id) timers[id] = nil; return true end,
  pull = function() clock = clock + 0.25 end,
}
package.loaded["kernel.net"] = {
  on = function(t, cb) nextId = nextId + 1; listeners[t] = listeners[t] or {}; table.insert(listeners[t], { id = nextId, cb = cb }); return nextId end,
  off = function(t, id) for i, l in ipairs(listeners[t] or {}) do if l.id == id then table.remove(listeners[t], i) end end end,
  send = function(to, pkt) sent[#sent + 1] = { to = to, pkt = pkt }; return true end,
  getAddress = function() return "manager-addr-0123456789abcdef" end,
}
package.loaded["kernel.net.protocol"] = {
  TYPE = setmetatable({}, { __index = function(_, k) return "T_" .. k end }),
  makePacket = function(t, p, o) return { type = t, payload = p, to = o and o.to } end,
}
package.loaded["log"] = { info = function() end, warn = function() end, error = function() end }
package.loaded["kernel.log"] = package.loaded["log"]

-- Config: the daemon reads /etc/cluster-manager.cfg through fs; give it one.
local MASTER = "master-addr-fedcba9876543210"
package.loaded["kernel.fs"] = {
  exists = function(p) return p == "/etc/cluster-manager.cfg" end,
  readFile = function(p)
    if p == "/etc/cluster-manager.cfg" then
      return 'return { master_address = "' .. MASTER .. '", hostname = "mgr-1", min_heartbeat_seconds = 2, max_heartbeat_seconds = 30 }'
    end
  end,
}

local mgr
for _, p in ipairs({
    "../TOS-Extras/cluster/manager-skeleton/usr/lib/cluster-manager.lua",
    "TOS-Extras/cluster/manager-skeleton/usr/lib/cluster-manager.lua" }) do
  local chunk = loadfile(p)
  if chunk then mgr = chunk(); break end
end
if not mgr then
  print("FAIL: could not load cluster-manager.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Helpers to play the Master.
local function deliver(typ, payload, from)
  for _, l in ipairs(listeners[typ] or {}) do l.cb({ type = typ, payload = payload }, from or MASTER) end
end
local function fireTimers()
  -- Run every pending one-shot (dispatch timers) and every interval once.
  for id, t in pairs(timers) do
    if not t.interval then timers[id] = nil end
    t.cb()
  end
end
local function sentOf(typ)
  local out = {}
  for _, s in ipairs(sent) do if s.pkt.type == typ then out[#out + 1] = s end end
  return out
end
local function clearSent() sent = {} end

print("=== cluster Manager lifecycle Tests ===")
print()

-- ── start + register ─────────────────────────────────────────────
print("-- start and register --")
test("start succeeds with a master_address", true, (mgr.start()))
test("a CLUSTER_REGISTER went out immediately", 1, #sentOf("T_CLUSTER_REGISTER"))
test("...to the Master", MASTER, sentOf("T_CLUSTER_REGISTER")[1].to)
test("...carrying the hostname", "mgr-1", sentOf("T_CLUSTER_REGISTER")[1].pkt.payload.hostname)
test("not registered before the ACK", false, mgr.status().registered)

deliver("T_CLUSTER_REGISTER_ACK", { accepted = true, domain_id = 7, heartbeat_interval = 10 }, "someone-else")
test("an ACK from a non-master is ignored", false, mgr.status().registered)
deliver("T_CLUSTER_REGISTER_ACK", { accepted = true, domain_id = 7, heartbeat_interval = 10 })
test("registered after the Master's ACK", true, mgr.status().registered)
test("domain id taken from the ACK", 7, mgr.status().domain_id)

-- ── heartbeat honours the negotiated interval ────────────────────
print()
print("-- heartbeat pacing --")
clearSent()
-- The interval timer ticks every 2 s (the floor); the Master asked for 10.
for _ = 1, 5 do clock = clock + 2; fireTimers() end   -- 10 s of ticks
local hb = #sentOf("T_CLUSTER_HEARTBEAT")
test("ten seconds of 2 s ticks under a 10 s interval: at most two heartbeats (first + one)", true, hb >= 1 and hb <= 2)
clearSent()
for _ = 1, 15 do clock = clock + 2; fireTimers() end   -- 30 s
hb = #sentOf("T_CLUSTER_HEARTBEAT")
test("thirty seconds: about three heartbeats, not fifteen", true, hb >= 2 and hb <= 4)
test("heartbeat carries the state", "active", sentOf("T_CLUSTER_HEARTBEAT")[1].pkt.payload.state)

-- ── an assignment runs and reports ───────────────────────────────
print()
print("-- assignment runs inline and reports once --")
clearSent()
deliver("T_CLUSTER_ASSIGN", { assignment_id = 1, job_id = 9,
  tasks_inline = { { code = "return _input * 2", input = 21 }, { code = "return 'x'" } } })
test("ACKed accepted", true, sentOf("T_CLUSTER_ASSIGN_ACK")[1].pkt.payload.accepted)
test("inflight from the ACK onward (before the dispatch timer)", 1, mgr.status().inflight_assignments)
test("no result yet", 0, #sentOf("T_CLUSTER_RESULT"))
fireTimers()                                            -- the 0.1 s dispatch
local res = sentOf("T_CLUSTER_RESULT")
test("exactly one result", 1, #res)
test("status ok", "ok", res[1].pkt.payload.status)
test("task 1 output", 42, res[1].pkt.payload.output_inline[1])
test("task 2 output", "x", res[1].pkt.payload.output_inline[2])
test("nothing inflight afterwards", 0, mgr.status().inflight_assignments)

-- ── the cancel-before-dispatch race ──────────────────────────────
print()
print("-- a cancel that lands between the ACK and the dispatch --")
clearSent()
local ran = false
package.loaded["computer"].uptime = function() return clock end
deliver("T_CLUSTER_ASSIGN", { assignment_id = 2, job_id = 9,
  tasks_inline = { { code = "return 1" } } })
deliver("T_CLUSTER_CANCEL", { assignment_id = 2 })     -- before the timer fires
test("the cancel produced no result on its own", 0, #sentOf("T_CLUSTER_RESULT"))
fireTimers()
res = sentOf("T_CLUSTER_RESULT")
test("exactly ONE result after the dispatch timer", 1, #res)
test("...and it says cancelled, not ok", "cancelled", res[1].pkt.payload.status)
test("...with nothing run", 1, res[1].pkt.payload.stats.cancelled_count)
test("nothing inflight afterwards", 0, mgr.status().inflight_assignments)

-- ── a cancel from a stranger ─────────────────────────────────────
print()
print("-- only the Master may cancel --")
clearSent()
deliver("T_CLUSTER_ASSIGN", { assignment_id = 3, job_id = 9, tasks_inline = { { code = "return 3" } } })
deliver("T_CLUSTER_CANCEL", { assignment_id = 3 }, "stranger-addr-0000000000000000")
deliver("T_CLUSTER_CANCEL", { assignment_id = 999 }, "stranger-addr-0000000000000000")
test("a stranger's cancels produce no results at all", 0, #sentOf("T_CLUSTER_RESULT"))
fireTimers()
res = sentOf("T_CLUSTER_RESULT")
test("the assignment ran normally", "ok", res[1] and res[1].pkt.payload.status)
test("...once", 1, #res)

-- ── a stale cancel from the Master ───────────────────────────────
clearSent()
deliver("T_CLUSTER_CANCEL", { assignment_id = 999 })
test("a Master cancel for an unknown id gets a best-effort cancelled result", "cancelled",
  sentOf("T_CLUSTER_RESULT")[1] and sentOf("T_CLUSTER_RESULT")[1].pkt.payload.status)

-- ── a cancel that arrives after the assignment already finished ──
-- Inline tasks run to completion inside the dispatch timer, so off-box
-- the only "late" cancel is one delivered right after it. That is the
-- stale path: the real result went out, and the cancel gets the
-- best-effort echo so the Master's view cannot stick in "running".
print()
print("-- a cancel after completion --")
clearSent()
deliver("T_CLUSTER_ASSIGN", { assignment_id = 4, job_id = 9,
  tasks_inline = { { code = "return 'first'" }, { code = "return 'second'" } } })
for id, t in pairs(timers) do
  if not t.interval then
    local cb = t.cb
    t.cb = function() cb(); deliver("T_CLUSTER_CANCEL", { assignment_id = 4 }) end
  end
end
fireTimers()
res = sentOf("T_CLUSTER_RESULT")
test("a cancel after completion yields the completed result plus a stale-cancel note (2 results)", 2, #res)
test("first is the real result", "ok", res[1].pkt.payload.status)
test("second is the stale-cancel echo", "cancel_for_unknown_inflight", res[2].pkt.payload.stats.reason)

-- ── validation ───────────────────────────────────────────────────
print()
print("-- validation --")
clearSent()
deliver("T_CLUSTER_ASSIGN", { assignment_id = 5, job_id = 9, tasks_inline = "not a list" })
test("tasks_inline that is not a table is rejected", false, sentOf("T_CLUSTER_ASSIGN_ACK")[1].pkt.payload.accepted)
test("...with a reason", "tasks_inline not a list", sentOf("T_CLUSTER_ASSIGN_ACK")[1].pkt.payload.reason)
clearSent()
deliver("T_CLUSTER_ASSIGN", { assignment_id = 6, job_id = 9 }, "stranger-addr-0000000000000000")
test("an ASSIGN from a stranger is dropped without an ACK", 0, #sentOf("T_CLUSTER_ASSIGN_ACK"))

-- ── honesty flag ─────────────────────────────────────────────────
test("status says whether mid-task cancel is possible on this host",
  type(debug) == "table" and type(debug.sethook) == "function", mgr.status().cancel_midtask)
test("status reports the task policy", "inline", mgr.status().task_execution)

-- ── task_execution: the operator's choice ────────────────────────
-- Pure routing first (no daemon state), then the whole daemon under
-- each policy. "inline" is the default and today's behaviour; "bridge"
-- keeps task code off this machine; "refuse" runs nothing at all.
print()
print("-- task_execution policy --")
do
  local rt = mgr._routeTask
  test("inline policy, no bridge -> inline",  "inline", rt({}, false, "opt-in", "inline"))
  test("refuse policy, no bridge -> refuse",  "refuse", rt({}, false, "opt-in", "refuse"))
  test("refuse policy still refuses with a bridge up when the task did not opt in",
       "refuse", rt({}, true, "opt-in", "refuse"))
  test("refuse policy lets an opted-in task use the bridge",
       "bridge", rt({ via_bridge = true }, true, "opt-in", "refuse"))
  test("bridge policy, bridge up -> bridge",  "bridge", rt({}, true,  "opt-in", "bridge"))
  test("bridge policy, no bridge -> refuse",  "refuse", rt({}, false, "opt-in", "bridge"))
  test("nil policy behaves as inline",        "inline", rt({}, false, "opt-in", nil))

  local ca = mgr._canAcceptTasks
  test("refuse: an assignment with tasks is not accepted", false, (ca(2, "refuse", false)))
  test("refuse: an EMPTY assignment still is",             true,  (ca(0, "refuse", false)))
  test("bridge with no bridge: not accepted",              false, (ca(2, "bridge", false)))
  test("bridge with a bridge: accepted",                   true,  (ca(2, "bridge", true)))
  test("inline: accepted",                                 true,  (ca(2, "inline", false)))
end

-- The daemon under task_execution = "refuse".
do
  mgr.stop()
  package.loaded["kernel.fs"].readFile = function(p)
    if p == "/etc/cluster-manager.cfg" then
      return 'return { master_address = "' .. MASTER .. '", hostname = "mgr-1", '
        .. 'task_execution = "refuse" }'
    end
  end
  timers, listeners, sent = {}, {}, {}
  mgr.start()
  deliver("T_CLUSTER_REGISTER_ACK", { accepted = true, domain_id = 7, heartbeat_interval = 5 })
  clearSent()
  deliver("T_CLUSTER_ASSIGN", { assignment_id = 20, job_id = 9,
    tasks_inline = { { code = "return 1" } } })
  local ack = sentOf("T_CLUSTER_ASSIGN_ACK")[1]
  test("refuse: the assignment is rejected at ACK time", false, ack.pkt.payload.accepted)
  test("...with a reason the Master can act on", "task_execution=refuse", ack.pkt.payload.reason)
  test("...and nothing is inflight", 0, mgr.status().inflight_assignments)
  fireTimers()
  test("...and no task ever ran", 0, #sentOf("T_CLUSTER_RESULT"))

  clearSent()
  deliver("T_CLUSTER_ASSIGN", { assignment_id = 21, job_id = 9, tasks_inline = {} })
  test("refuse: an assignment with no tasks is still accepted", true,
    sentOf("T_CLUSTER_ASSIGN_ACK")[1].pkt.payload.accepted)
  fireTimers()
  test("...and reports ok", "ok", sentOf("T_CLUSTER_RESULT")[1].pkt.payload.status)
  test("status reports the policy", "refuse", mgr.status().task_execution)
end

-- The daemon under task_execution = "bridge" with no bridge configured.
do
  mgr.stop()
  package.loaded["kernel.fs"].readFile = function(p)
    if p == "/etc/cluster-manager.cfg" then
      return 'return { master_address = "' .. MASTER .. '", hostname = "mgr-1", '
        .. 'task_execution = "bridge" }'
    end
  end
  timers, listeners, sent = {}, {}, {}
  mgr.start()
  deliver("T_CLUSTER_REGISTER_ACK", { accepted = true, domain_id = 7, heartbeat_interval = 5 })
  clearSent()
  deliver("T_CLUSTER_ASSIGN", { assignment_id = 22, job_id = 9,
    tasks_inline = { { code = "return 1" } } })
  local ack = sentOf("T_CLUSTER_ASSIGN_ACK")[1]
  test("bridge with no worker: rejected rather than run here", false, ack.pkt.payload.accepted)
  test("...saying which policy and why", true,
    (ack.pkt.payload.reason or ""):find("no worker bridge", 1, true) ~= nil)
end

-- An unknown policy string falls back to inline rather than failing shut.
do
  mgr.stop()
  package.loaded["kernel.fs"].readFile = function(p)
    if p == "/etc/cluster-manager.cfg" then
      return 'return { master_address = "' .. MASTER .. '", hostname = "mgr-1", '
        .. 'task_execution = "yes please" }'
    end
  end
  timers, listeners, sent = {}, {}, {}
  mgr.start()
  test("a typo'd policy is corrected to inline", "inline", mgr.status().task_execution)
  deliver("T_CLUSTER_REGISTER_ACK", { accepted = true, domain_id = 7, heartbeat_interval = 5 })
  clearSent()
  deliver("T_CLUSTER_ASSIGN", { assignment_id = 23, job_id = 9,
    tasks_inline = { { code = "return 5" } } })
  fireTimers()
  test("...and tasks run", 5, sentOf("T_CLUSTER_RESULT")[1].pkt.payload.output_inline[1])
end

-- Back to the default for the sections below.
mgr.stop()
package.loaded["kernel.fs"].readFile = function(p)
  if p == "/etc/cluster-manager.cfg" then
    return 'return { master_address = "' .. MASTER .. '", hostname = "mgr-1" }'
  end
end
timers, listeners, sent = {}, {}, {}
mgr.start()
deliver("T_CLUSTER_REGISTER_ACK", { accepted = true, domain_id = 7, heartbeat_interval = 5 })

-- ── drain + stop ─────────────────────────────────────────────────
print()
print("-- drain and stop --")
clearSent()
mgr.drain()
deliver("T_CLUSTER_ASSIGN", { assignment_id = 7, job_id = 9, tasks_inline = {} })
test("draining rejects assignments", false, sentOf("T_CLUSTER_ASSIGN_ACK")[1].pkt.payload.accepted)
test("...saying so", "draining", sentOf("T_CLUSTER_ASSIGN_ACK")[1].pkt.payload.reason)
mgr.undrain()
test("stop succeeds", true, mgr.stop())
test("stopped status", false, mgr.status().running)
local left = 0; for _ in pairs(timers) do left = left + 1 end
test("no timers left behind", 0, left)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
