-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a Manager follows a task pointer             ║
-- ║                                                                ║
-- ║  When a job's task list is too big for a packet the Master     ║
-- ║  writes it to the Storage Node and sends the Manager a pointer ║
-- ║  (tasks_ref). Nothing on the Manager ever read one.            ║
-- ║  dispatchAssignment took `p.tasks_inline or {}`, so a spilled  ║
-- ║  assignment ran no tasks, reported ok, and the job read done   ║
-- ║  with none of its work run. Every test of tasks_ref stopped    ║
-- ║  at the Master.                                                ║
-- ║                                                                ║
-- ║  Drives the real daemon, real protocol and real serializer     ║
-- ║  through the same stubs as test_cluster_manager_lifecycle,     ║
-- ║  with a fake modem playing the Storage Node.                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_tasks_ref.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local clock = 100
local sent, timers, netListeners, modemListeners = {}, {}, {}, {}
local nextId = 0

package.loaded["filesystem"] = { exists = function() return false end }
package.loaded["computer"] = { uptime = function() return clock end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 1e6 end }
package.loaded["event"] = {
  on = function(sig, cb)
    nextId = nextId + 1
    if sig == "modem_message" then modemListeners[nextId] = cb end
    return nextId
  end,
  off = function(sig, id) if sig == "modem_message" then modemListeners[id] = nil end end,
  interval = function(delay, cb) nextId = nextId + 1; timers[nextId] = { delay = delay, cb = cb, interval = true }; return nextId end,
  timer = function(delay, cb) nextId = nextId + 1; timers[nextId] = { delay = delay, cb = cb }; return nextId end,
  cancelTimer = function(id) timers[id] = nil; return true end,
  pull = function() clock = clock + 0.25 end,
}
package.loaded["kernel.event"] = package.loaded["event"]
package.loaded["kernel.net"] = {
  on = function(t, cb) nextId = nextId + 1; netListeners[t] = netListeners[t] or {}; table.insert(netListeners[t], cb); return nextId end,
  off = function() end,
  send = function(to, pkt) sent[#sent + 1] = { to = to, pkt = pkt }; return true end,
  getAddress = function() return "manager-addr-0123456789abcdef" end,
}
package.loaded["kernel.net.protocol"] = {
  TYPE = setmetatable({}, { __index = function(_, k) return "T_" .. k end }),
  makePacket = function(t, p, o) return { type = t, payload = p, to = o and o.to } end,
}
package.loaded["log"] = { info = function() end, warn = function() end, error = function() end }
package.loaded["kernel.log"] = package.loaded["log"]

local MASTER, NODE = "master-addr-fedcba9876543210", "node-addr-0123456789abcdef00"
package.loaded["kernel.fs"] = {
  exists = function(p) return p == "/etc/cluster-manager.cfg" end,
  readFile = function(p)
    if p == "/etc/cluster-manager.cfg" then
      return 'return { master_address = "' .. MASTER .. '", hostname = "mgr-1" }'
    end
  end,
}

local serialize = require("kernel.serialize")
package.loaded["kernel.ipc"] = nil

local function loadAny(rel)
  for _, b in ipairs({ "../TOS-Extras/", "TOS-Extras/" }) do
    local chunk = loadfile(b .. rel)
    if chunk then return chunk() end
  end
  error("cannot load " .. rel)
end
local cproto = loadAny("cluster/manager-skeleton/usr/lib/cluster/protocol.lua")
package.loaded["cluster.protocol"] = cproto
local PORT = cproto.PORT.PUBLIC_READ

-- The Storage Node, as seen through this machine's modem.
local requests, openPorts, sendFails = {}, {}, false
local myAddr = "modem-1"
local modem = {
  isOpen = function(p) return openPorts[p] == true end,
  open = function(p) openPorts[p] = true; return true end,
  close = function(p) openPorts[p] = nil; return true end,
  send = function(addr, port, data)
    if sendFails then error("no route") end
    requests[#requests + 1] = { addr = addr, port = port, msg = serialize.decode(data) }
    return true
  end,
}
package.loaded["component"] = {
  list = function(t) local done = false
    return function() if not done and t == "modem" then done = true; return myAddr end end
  end,
  proxy = function() return modem end,
  isAvailable = function() return true end,
}

local mgr = loadAny("cluster/manager-skeleton/usr/lib/cluster-manager.lua")

local function deliver(typ, payload, from)
  for _, cb in ipairs(netListeners[typ] or {}) do cb({ type = typ, payload = payload }, from or MASTER) end
end
local function fireOneShots()
  local due = {}
  for id, t in pairs(timers) do
    if not t.interval then due[#due + 1] = id end
  end
  for _, id in ipairs(due) do
    local t = timers[id]
    if t then timers[id] = nil; t.cb() end
  end
end
local function hear(from, port, reply)
  local data = type(reply) == "string" and reply or serialize.encode(reply)
  for _, cb in pairs(modemListeners) do cb("modem_message", "modem-1", from, port, 0, data) end
end
local function resultsOf(id)
  local out = {}
  for _, s in ipairs(sent) do
    if s.pkt.type == "T_CLUSTER_RESULT" and s.pkt.payload.assignment_id == id then
      out[#out + 1] = s.pkt.payload
    end
  end
  return out
end
local function assign(id, extra)
  local p = { assignment_id = id, job_id = 9, tasks_ref = "public://job-9/tasks/assignment-" .. id,
              store_addr = NODE }
  for k, v in pairs(extra or {}) do p[k] = v end
  deliver("T_CLUSTER_ASSIGN", p)
  fireOneShots()
end
local function accepted(id)
  for _, s in ipairs(sent) do
    if s.pkt.type == "T_CLUSTER_ASSIGN_ACK" and s.pkt.payload.assignment_id == id then
      return s.pkt.payload.accepted, s.pkt.payload.reason
    end
  end
end
local function res(id, fields)
  local r = { magic = cproto.PUB_MAGIC, op = "RES", key = "k", req_id = id, chunk = 1, total = 1 }
  for k, v in pairs(fields or {}) do r[k] = v end
  return r
end

assert(mgr.start())
deliver("T_CLUSTER_REGISTER_ACK", { accepted = true, domain_id = 7, heartbeat_interval = 10 })

local TASKS = serialize.encode({ { code = "return 21 * 2" }, { code = "return 'second'" } })

print("=== a pointer is followed ===")
do
  sent, requests = {}, {}
  assign(1)
  test("it was accepted", (accepted(1)) == true)
  test("no result yet: the tasks are not here", #resultsOf(1) == 0)
  test("one read went to the node named in the assignment",
    #requests == 1 and requests[1].addr == NODE, requests[1] and requests[1].addr)
  test("on the read port", requests[1] and requests[1].port == PORT)
  test("for the key, without the scheme",
    requests[1] and requests[1].msg.key == "job-9/tasks/assignment-1", requests[1] and requests[1].msg.key)
  test("the read port is held open for the answer", openPorts[PORT] == true)
  hear(NODE, PORT, res(1, { data = TASKS }))
  local r = resultsOf(1)
  test("the tasks ran", #r == 1 and r[1].status == "ok", r[1] and r[1].status)
  test("both of them", r[1] and r[1].stats and r[1].stats.task_count == 2, r[1] and r[1].stats and r[1].stats.task_count)
  test("with their real answers", r[1] and r[1].output_inline and r[1].output_inline[1] == 42
    and r[1].output_inline[2] == "second")
  test("the port is given back", openPorts[PORT] == nil)
  test("the listener is gone", next(modemListeners) == nil)
end

print("=== chunks, in any order ===")
do
  sent, requests = {}, {}
  assign(2)
  local a, b = TASKS:sub(1, 20), TASKS:sub(21)
  hear(NODE, PORT, res(2, { data = b, chunk = 2, total = 2 }))
  test("one chunk of two runs nothing", #resultsOf(2) == 0)
  hear(NODE, PORT, res(2, { data = b, chunk = 2, total = 2 }))
  test("a repeated chunk does not count twice", #resultsOf(2) == 0)
  hear(NODE, PORT, res(2, { data = a, chunk = 1, total = 2 }))
  local r = resultsOf(2)
  test("the last chunk completes it", #r == 1 and r[1].status == "ok", r[1] and r[1].status)
end

print("=== nothing else can answer ===")
do
  sent, requests = {}, {}
  assign(3)
  local bad = serialize.encode({ { code = "return 'forged'" } })
  hear("stranger-addr", PORT, res(3, { data = bad }))
  hear(NODE, PORT + 1, res(3, { data = bad }))
  hear(NODE, PORT, res(99, { data = bad }))
  hear(NODE, PORT, "not a table at all {{{")
  test("a stranger, a wrong port, a wrong id and junk run nothing", #resultsOf(3) == 0)
  hear(NODE, PORT, res(3, { data = TASKS }))
  test("the real answer still lands", #resultsOf(3) == 1 and resultsOf(3)[1].status == "ok")
end

print("=== a pointer that cannot be followed is a failure, never an empty success ===")
do
  sent, requests = {}, {}
  assign(4)
  hear(NODE, PORT, res(4, { err = "no_such_key" }))
  local r = resultsOf(4)
  test("a key the node lost fails the assignment", #r == 1 and r[1].status == "failed", r[1] and r[1].status)
  test("and says why", r[1] and tostring(r[1].errors[1]):find("no_such_key", 1, true) ~= nil)
  test("the port is given back", openPorts[PORT] == nil)
end
do
  sent, requests = {}, {}
  assign(5)
  clock = clock + 20
  fireOneShots()
  local r = resultsOf(5)
  test("a node that never answers fails it", #r == 1 and r[1].status == "failed", r[1] and r[1].status)
  test("and says so", r[1] and tostring(r[1].errors[1]):find("timed out", 1, true) ~= nil)
  test("nothing is left listening", next(modemListeners) == nil)
end
do
  sent, requests = {}, {}
  assign(6)
  hear(NODE, PORT, res(6, { data = "not lua at all {{{" }))
  local r = resultsOf(6)
  test("a list that does not decode fails it", #r == 1 and r[1].status == "failed", r[1] and r[1].status)
end
do
  sent, requests = {}, {}
  sendFails = true
  assign(7)
  sendFails = false
  local r = resultsOf(7)
  test("a read that cannot be sent fails it", #r == 1 and r[1].status == "failed", r[1] and r[1].status)
end

print("=== a node on this machine is read directly ===")
do
  -- cluster-storage installs a Manager beside it, and no modem can send to
  -- itself, so this is the shape a two-box cluster takes.
  sent, requests = {}, {}
  myAddr = NODE
  package.loaded["cluster.store"] = { get = function(key)
    if key:find("assignment%-11$") then return TASKS end
    return nil, "no_such_key"
  end }
  assign(11)
  test("nothing goes out on the air", #requests == 0)
  test("the tasks ran", #resultsOf(11) == 1 and resultsOf(11)[1].status == "ok",
    resultsOf(11)[1] and resultsOf(11)[1].status)
  assign(12)
  test("a key the local store lost still fails",
    #resultsOf(12) == 1 and resultsOf(12)[1].status == "failed")
  package.loaded["cluster.store"] = nil
  myAddr = "modem-1"
end

print("=== the shape is checked up front ===")
do
  sent = {}
  deliver("T_CLUSTER_ASSIGN", { assignment_id = 8, job_id = 9, tasks_ref = "public://x" })
  local ok, why = accepted(8)
  test("a pointer with no node is refused at the ACK", ok == false, ok)
  test("with a reason", tostring(why):find("store_addr", 1, true) ~= nil, why)
end

print("=== an inline assignment is untouched ===")
do
  sent, requests = {}, {}
  deliver("T_CLUSTER_ASSIGN", { assignment_id = 10, job_id = 9, tasks_inline = { { code = "return 1" } } })
  fireOneShots()
  test("no read goes out", #requests == 0)
  test("it runs", #resultsOf(10) == 1 and resultsOf(10)[1].status == "ok")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
