-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: Master <-> Storage Node over a modelled radio            ║
-- ║                                                              ║
-- ║  test_storaged.lua drives the daemon's handlers directly, and   ║
-- ║  test_cluster_jobs.lua drives the Master's client against a      ║
-- ║  scripted node. Neither can notice that the two halves never      ║
-- ║  actually meet: both fakes DELIVER messages that a real OC         ║
-- ║  modem would throw away.                                            ║
-- ║                                                                      ║
-- ║  An OC modem delivers a message only if the destination holds        ║
-- ║  that PORT OPEN. kernel.net opens exactly one (its listenPort),        ║
-- ║  while the Master sends STORE_PUT to 2101 and a Worker sends its         ║
-- ║  reads to 2100. The daemon opened neither, so its package was a            ║
-- ║  node nothing could talk to -- and the Master quietly fell back to          ║
-- ║  inline payloads, which is why nothing ever looked broken.                   ║
-- ║                                                                                ║
-- ║  So this models the air: a send lands only on an open port, and the              ║
-- ║  kernel stand-in routes inbound TOS packets by TYPE and ignores the                ║
-- ║  port, as kernel/net/init.lua does. Then the real store_client talks to              ║
-- ║  the real daemon, and an OpenOS-style worker reads over raw framing.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua cluster/storage-skeleton/test_storage_wire.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ", want " .. tostring(expected) .. ")",
    expected == actual)
end
local function has(s, sub) return type(s) == "string" and s:find(sub, 1, true) ~= nil end

local ROOT = "cluster/storage-skeleton/"
local DEV  = "../TOS-Dev/"
local LISTEN = 42     -- kernel.net's listenPort default

local serialize = assert(loadfile(DEV .. "tos/kernel/serialize.lua"))()
local cproto = assert(loadfile(ROOT .. "../manager-skeleton/usr/lib/cluster/protocol.lua"))()

local clock = { uptime = function() return 1000 end }

local function freshProtocol()
  local env = setmetatable({ require = function(n)
    if n == "computer" then return clock end
    if n == "kernel.serialize" then return serialize end
    error("not stubbed: " .. n, 2)
  end }, { __index = _G })
  return assert(loadfile(DEV .. "tos/kernel/net/protocol.lua", "t", env))()
end
local protocol = freshProtocol()

local function fsStub()
  local files, dirs = {}, {}
  return {
    makeDirectory = function(p) dirs[p] = true; return true end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, d) files[p] = d; return true end,
    remove = function(p) files[p] = nil; return true end,
    rename = function(a, b) files[b] = files[a]; files[a] = nil; return true end,
    spaceTotal = function() return 1024 * 1024 end,
  }
end

-- ══════════════════════════════════════════════════════════════════
-- The air, and a machine on it
-- ══════════════════════════════════════════════════════════════════
local function newAir() return { modems = {}, dropped = {} } end

--- `maxPorts` models a Tier-1 wireless card, which holds one open port.
local function newMachine(air, addr, maxPorts)
  local m = { address = addr, ports = {}, nports = 0, inbox = {} }
  local listeners = {}      -- signal -> { {id, fn} }
  local nextId = 1
  local ev = {}
  function ev.on(signal, fn)
    listeners[signal] = listeners[signal] or {}
    local id = nextId; nextId = nextId + 1
    table.insert(listeners[signal], { id = id, fn = fn })
    return id
  end
  function ev.off(signal, id)
    for i, e in ipairs(listeners[signal] or {}) do
      if e.id == id then table.remove(listeners[signal], i); return true end
    end
    return false
  end
  function ev.count(signal) return #(listeners[signal] or {}) end
  function ev.interval() return 0 end
  function ev.cancelTimer() end
  function ev.fire(signal, ...)
    for _, e in ipairs({ table.unpack(listeners[signal] or {}) }) do e.fn(signal, ...) end
  end

  local modem = {}
  function modem.open(port)
    if m.ports[port] then return false end
    if maxPorts and m.nports >= maxPorts then error("too many open ports") end
    m.ports[port] = true; m.nports = m.nports + 1
    return true
  end
  function modem.close(port)
    if m.ports[port] then m.ports[port] = nil; m.nports = m.nports - 1; return true end
    return false
  end
  function modem.send(to, port, data)
    local dest = air.modems[to]
    if dest and dest.ports[port] then
      dest.event.fire("modem_message", to, addr, port, 1, data)
      return true
    end
    air.dropped[#air.dropped + 1] = { from = addr, to = to, port = port }
    return true      -- a real send does not report a closed remote port
  end
  m.modem, m.event = modem, ev
  air.modems[addr] = m

  -- A stand-in for kernel.net: opens ONLY its listenPort, routes inbound
  -- TOS packets by type with the PORT IGNORED (kernel/net/init.lua's
  -- handleIncoming never reads it), and sends on listenPort unless told.
  local handlers = {}
  local net = {}
  function net.on(kind, fn) handlers[kind] = fn; return kind end
  function net.off(kind) handlers[kind] = nil end
  function net.getProtocol() return protocol end
  function net.send(to, packet, port)
    packet.from = addr
    modem.send(to, port or LISTEN, packet)
    return true
  end
  function net.waitFor() end      -- delivery is synchronous in this model
  modem.open(LISTEN)
  ev.on("modem_message", function(_, _, remote, port, _, data)
    if type(data) == "table" and data.type and handlers[data.type] then
      handlers[data.type](data, remote)
    end
  end)
  m.net = net
  return m
end

-- ══════════════════════════════════════════════════════════════════
-- The daemon and the Master's client, loaded as the package would
-- ══════════════════════════════════════════════════════════════════
local function freshStoraged(deps)
  local function req(name)
    if name == "computer" then return clock end
    if name == "kernel.fs" then return deps.fs end
    if name == "kernel.serialize" then return serialize end
    if name == "kernel.log" then return deps.log end
    if name == "cluster.store" then return deps.store end
    error("sandbox: module '" .. name .. "' not stubbed for this test", 2)
  end
  local env = setmetatable({ require = req }, { __index = _G })
  return assert(loadfile(ROOT .. "usr/lib/cluster-storaged.lua", "t", env))()
end

local function freshClient(net, nodeAddr)
  local env = setmetatable({ require = function(n)
    if n == "computer" then return clock end
    error("not stubbed: " .. n, 2)
  end }, { __index = _G })
  local client = assert(loadfile(ROOT .. "../master-skeleton/lib/cluster/store_client.lua", "t", env))()
  client.init({ net = net, protocol = protocol, serialize = serialize,
                state = { _data = { storage_node = { address = nodeAddr } } },
                log = { info = function() end, warn = function() end, error = function() end } })
  return client
end

local function logCapture()
  local lines = {}
  local function add(level) return function(_, msg) lines[#lines + 1] = level .. ": " .. tostring(msg) end end
  return { info = add("info"), warn = add("warn"), error = add("error") }, lines
end

--- A node on the air, started the way the rc service starts it.
local function bringUp(air, addr, masterAddr, maxPorts)
  local node = newMachine(air, addr, maxPorts)
  local log, lines = logCapture()
  local storedChunk = assert(loadfile(ROOT .. "usr/lib/cluster/store.lua"))
  local d = freshStoraged({ fs = fsStub(), store = storedChunk(), log = log })
  d._internal.setConfig(nil)
  local ok, err = d.start({
    net = node.net, cproto = cproto, protocol = protocol, event = node.event,
    modems = { { address = addr, proxy = node.modem } },
    config_path = "/etc/cluster-storage.cfg",
  })
  d.config().master = masterAddr
  return d, node, ok, err, lines
end

print("=== Master <-> Storage Node over a modelled radio ===")
print()

-- ── The write plane: the Master's real client, the real daemon ─────────
do
  local air = newAir()
  local master = newMachine(air, "master-0001")
  local d, node, ok = bringUp(air, "node-0001", "master-0001")
  test("the daemon starts", ok and d.isRunning())

  test("it holds the write port open", node.ports[2101] == true)
  test("...and the read port", node.ports[2100] == true)
  test("...and has not evicted the kernel's own listen port", node.ports[LISTEN] == true)

  local client = freshClient(master.net, "node-0001")
  local ack, err = client.put("job-7/tasks/assignment-1", "payload bytes", { ttl = 600 })
  test("the Master's STORE_PUT is acknowledged", ack ~= nil)
  eq("...with no error", nil, err)
  eq("...naming the key", "job-7/tasks/assignment-1", ack and ack.key)
  test("...and a lease the Master can use later", ack and ack.lease_id ~= nil)
  eq("nothing was dropped on a closed port", 0, #air.dropped)

  local rel, rerr = client.release("job-7/tasks/assignment-1", ack and ack.lease_id)
  test("a release with the right lease is acknowledged", rel ~= nil and rerr == nil)

  local _, denied = freshClient(newMachine(air, "intruder-01").net, "node-0001")
    .put("shared/x", "nope")
  eq("a sender the operator did not declare is refused by name", "unknown_writer", denied)
end

-- ── The read plane: an OpenOS-style worker, raw framing ───────────────
do
  local air = newAir()
  local master = newMachine(air, "master-0001")
  local d, node = bringUp(air, "node-0001", "master-0001")
  local client = freshClient(master.net, "node-0001")
  client.put("shared/dataset", "the public value", { ttl = 600 })

  -- A worker has no TOS stack: it opens 2100, sends a bare table, and
  -- reads whatever comes back on the same port.
  local worker = newMachine(air, "worker-0001")
  worker.modem.open(2100)
  local replies = {}
  worker.event.on("modem_message", function(_, _, _, port, _, data)
    if port == 2100 and type(data) == "string" then replies[#replies + 1] = serialize.decode(data) end
  end)
  worker.modem.send("node-0001", 2100,
    serialize.encode({ magic = "PUB", op = "GET", key = "shared/dataset", req_id = 5 }))
  eq("a worker's GET is answered", 1, #replies)
  eq("...with the stored value", "the public value", replies[1] and replies[1].data)
  eq("...tagged with its request id", 5, replies[1] and replies[1].req_id)

  worker.modem.send("node-0001", 2100,
    serialize.encode({ magic = "PUB", op = "LIST", prefix = "shared/", req_id = 6 }))
  eq("a LIST is answered too", 2, #replies)
  eq("...with the key", "shared/dataset", replies[2] and replies[2].keys and replies[2].keys[1])

  --! The listener must be port-selective: the node also hears every TOS
  --! packet, and a PUB handler that fired on those would treat a STORE_PUT
  --! frame as a malformed read.
  local before = #replies
  worker.modem.send("node-0001", LISTEN, serialize.encode({ magic = "PUB", op = "GET", key = "shared/dataset", req_id = 7 }))
  eq("a PUB frame on some other port is not served", before, #replies)

  eq("while running, the node holds the kernel's listener plus its own", 2,
    node.event.count("modem_message"))
  d.stop()
  eq("after stop only the kernel's listener is left", 1, node.event.count("modem_message"))
  worker.modem.send("node-0001", 2100,
    serialize.encode({ magic = "PUB", op = "GET", key = "shared/dataset", req_id = 8 }))
  eq("after stop the node answers nothing", before, #replies)
  test("...because its ports are closed", not node.ports[2100] and not node.ports[2101])
  --! Closed ports alone would hide a leaked listener (nothing arrives to
  --! reach it). Deliver one by hand, as another service holding the port
  --! open would cause, and the stopped node must still stay silent.
  node.event.fire("modem_message", "node-0001", "worker-0001", 2100, 1,
    serialize.encode({ magic = "PUB", op = "GET", key = "shared/dataset", req_id = 9 }))
  eq("a stopped node stays silent even if a frame is delivered", before, #replies)
  test("...and the kernel's listen port is untouched", node.ports[LISTEN] == true)
  test("...the request was dropped on the closed port, as a real modem would",
    #air.dropped >= 1 and air.dropped[#air.dropped].port == 2100)
end

-- ── A node that cannot open its ports says so ──────────────────────────
do
  local air = newAir()
  local master = newMachine(air, "master-0001")
  --! maxPorts = 1: a Tier-1 wireless card. kernel.net already holds the
  --! one slot, so the daemon's open() raises.
  local d, node, ok, _, lines = bringUp(air, "node-0001", "master-0001", 1)
  test("start still succeeds (the node may have a second NIC)", ok)
  test("...but the ports are NOT open", not node.ports[2101] and not node.ports[2100])
  local text = table.concat(lines, "\n")
  test("a warning names the modem that could not open them", has(text, "could not open ports"))
  test("...and says why", has(text, "Tier-1"))
  test("...and an error says nothing can reach the node", has(text, "nothing can reach this node"))

  local ack, err = freshClient(master.net, "node-0001").put("shared/x", "v")
  eq("the Master's write goes nowhere", nil, ack)
  eq("...and times out rather than pretending", "timeout", err)
  test("...the frame was dropped on the closed port", #air.dropped >= 1 and air.dropped[1].port == 2101)
end

-- ── Idempotent start ───────────────────────────────────────────────────
do
  local air = newAir()
  local master = newMachine(air, "master-0001")
  local d, node = bringUp(air, "node-0001", "master-0001")
  local ok = d.start({ net = node.net, cproto = cproto, protocol = protocol, event = node.event })
  eq("starting a running node is a no-op success", true, ok)

  local worker = newMachine(air, "worker-0001")
  worker.modem.open(2100)
  local n = 0
  worker.event.on("modem_message", function(_, _, _, port) if port == 2100 then n = n + 1 end end)
  worker.modem.send("node-0001", 2100,
    serialize.encode({ magic = "PUB", op = "LIST", prefix = "", req_id = 1 }))
  eq("...and the read plane is not registered twice (one reply, not two)", 1, n)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
