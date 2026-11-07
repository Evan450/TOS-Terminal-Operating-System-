-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: a storage POOL -- placement, replicas, quorum, repair   ║
-- ║                                                              ║
-- ║  storage-spec-draft.md §5 and the answers approved on          ║
-- ║  2026-11-07 (§10): placement is a pure function of the key      ║
-- ║  (no coordinator), job-<id>/ goes to two members, shared/ to     ║
-- ║  all of them and stands at a majority, versions decide which      ║
-- ║  copy wins, leases stay with the member that issued them, and      ║
-- ║  a LIST names every member that did not answer.                     ║
-- ║                                                                      ║
-- ║  Built on test_storage_wire.lua's modelled radio, so the Master's     ║
-- ║  REAL client talks to three REAL daemons, and a member is "down"       ║
-- ║  the way one is in a world: its frames go nowhere.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua cluster/storage-skeleton/test_storage_pool.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ", want " .. tostring(expected) .. ")",
    expected == actual)
end
local function has(s, sub) return type(s) == "string" and s:find(sub, 1, true) ~= nil end

local ROOT = "cluster/storage-skeleton/"
local DEV  = "../TOS-Dev/"
do
  local f = io.open(DEV .. "tos/kernel/serialize.lua", "rb")
  if f then f:close() else DEV = "../" end
end
local LISTEN = 42

local serialize = assert(loadfile(DEV .. "tos/kernel/serialize.lua"))()
local cproto = assert(loadfile(ROOT .. "../manager-skeleton/usr/lib/cluster/protocol.lua"))()
local placement = assert(loadfile(ROOT .. "../master-skeleton/lib/cluster/placement.lua"))()

local clock = { uptime = function() return 1000 end }

local protocol
do
  local env = setmetatable({ require = function(n)
    if n == "computer" then return clock end
    if n == "kernel.serialize" then return serialize end
    error("not stubbed: " .. n, 2)
  end }, { __index = _G })
  protocol = assert(loadfile(DEV .. "tos/kernel/net/protocol.lua", "t", env))()
end

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
-- The air (as test_storage_wire.lua), plus taking a machine off it
-- ══════════════════════════════════════════════════════════════════
local function newAir() return { modems = {}, dropped = {}, away = {} } end

local function newMachine(air, addr)
  local m = { address = addr, ports = {}, nports = 0 }
  local listeners, nextId = {}, 1
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
  function ev.interval() return 0 end
  function ev.cancelTimer() end
  function ev.fire(signal, ...)
    for _, e in ipairs({ table.unpack(listeners[signal] or {}) }) do e.fn(signal, ...) end
  end

  local modem = {}
  function modem.open(port)
    if m.ports[port] then return false end
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
    return true
  end
  m.modem, m.event = modem, ev
  air.modems[addr] = m

  local handlers = {}
  local net = {}
  function net.on(kind, fn) handlers[kind] = fn; return kind end
  function net.off(kind) handlers[kind] = nil end
  function net.getProtocol() return protocol end
  function net.getAddress() return addr end
  function net.send(to, packet, port)
    packet.from = addr
    -- Through the serializer, as kernel.net would: a field that does not
    -- survive encoding (a version, a lease map) must fail here, not in a world.
    local wire = serialize.decode(serialize.encode(packet))
    modem.send(to, port or LISTEN, wire)
    return true
  end
  function net.waitFor() end
  modem.open(LISTEN)
  ev.on("modem_message", function(_, _, remote, port, _, data)
    if type(data) == "table" and data.type and handlers[data.type] then
      handlers[data.type](data, remote)
    end
  end)
  m.net = net
  return m
end

local function down(air, addr) air.away[addr] = air.modems[addr]; air.modems[addr] = nil end
local function up(air, addr) air.modems[addr] = air.away[addr]; air.away[addr] = nil end

local function freshStoraged(deps)
  local env = setmetatable({ require = function(name)
    if name == "computer" then return clock end
    if name == "kernel.fs" then return deps.fs end
    if name == "kernel.serialize" then return serialize end
    if name == "kernel.log" then return deps.log end
    if name == "cluster.store" then return deps.store end
    error("sandbox: module '" .. name .. "' not stubbed for this test", 2)
  end }, { __index = _G })
  return assert(loadfile(ROOT .. "usr/lib/cluster-storaged.lua", "t", env))()
end

local QUIET = { info = function() end, warn = function() end, error = function() end }

local function bringUp(air, addr, masterAddr)
  local node = newMachine(air, addr)
  local store = assert(loadfile(ROOT .. "usr/lib/cluster/store.lua"))()
  local d = freshStoraged({ fs = fsStub(), store = store, log = QUIET })
  d._internal.setConfig(nil)
  assert(d.start({
    net = node.net, cproto = cproto, protocol = protocol, event = node.event,
    modems = { { address = addr, proxy = node.modem } },
    config_path = "/etc/cluster-storage.cfg",
  }))
  d.config().master = masterAddr
  return { d = d, node = node, store = store }
end

local function freshClient(net, pool, stateRef)
  local env = setmetatable({ require = function(n)
    if n == "computer" then return clock end
    error("not stubbed: " .. n, 2)
  end }, { __index = _G })
  local client = assert(loadfile(ROOT .. "../master-skeleton/lib/cluster/store_client.lua", "t", env))()
  client.init({ net = net, protocol = protocol, serialize = serialize,
                state = stateRef or { _data = {} }, log = QUIET,
                pool = pool, placement = placement })
  return client
end

-- A pool of three on one air, and the Master's client.
local MEMBERS = { "node-aaaa", "node-bbbb", "node-cccc" }
local function pool3()
  local air = newAir()
  local master = newMachine(air, "master-0001")
  local nodes = {}
  for _, a in ipairs(MEMBERS) do nodes[a] = bringUp(air, a, "master-0001") end
  return air, master, nodes
end

-- A key whose placement includes (or excludes) a given member.
local function jobKeyWith(addr, want)
  for i = 1, 500 do
    local k = "job-9/tasks/assignment-" .. i
    local t = placement.targets(k, MEMBERS)
    local inIt = t.addrs[1] == addr or t.addrs[2] == addr
    if inIt == want then return k, t end
  end
end

print("=== placement is a pure function of the key ===")
do
  eq("the hash is deterministic", placement.hash("job-1/x\0node-a"), placement.hash("job-1/x\0node-a"))
  test("...and 32-bit", placement.hash("anything") >= 0 and placement.hash("anything") <= 0xFFFFFFFF)

  for _, k in ipairs({ "job-12/tasks/a", "domain-3/scratch/x", "shared/config", "weird/thing" }) do
    local ns = placement.namespace(k)
    local parsed = cproto.parseKey(k)
    local want = parsed and parsed.ns or "other"
    eq("namespace of " .. k .. " agrees with cluster.protocol.parseKey", want, ns)
  end

  local a = placement.targets("job-4/tasks/assignment-1", { "node-cccc", "node-aaaa", "node-bbbb" })
  local b = placement.targets("job-4/tasks/assignment-1", { "node-bbbb", "node-cccc", "node-aaaa", "node-aaaa" })
  eq("job- keys go to two members", 2, #a.addrs)
  test("...two different ones", a.addrs[1] ~= a.addrs[2])
  eq("...and both must take it", 2, a.need)
  test("the order members are listed in, or a repeat, changes nothing",
    a.addrs[1] == b.addrs[1] and a.addrs[2] == b.addrs[2])

  local s3 = placement.targets("shared/cfg", MEMBERS)
  eq("shared/ goes to every member", 3, #s3.addrs)
  eq("...standing at a majority of three", 2, s3.need)
  eq("...and of four", 3, placement.targets("shared/cfg", { "a", "b", "c", "d" }).need)
  eq("...and of one", 1, placement.targets("shared/cfg", { "a" }).need)

  local d = placement.targets("domain-5/scratch", MEMBERS, { domainOwners = { [5] = "node-bbbb" } })
  test("domain-<id>/ lives on the member that owns the domain", #d.addrs == 1 and d.addrs[1] == "node-bbbb")
  local d2 = placement.targets("domain-6/scratch", MEMBERS, { domainOwners = { [6] = "elsewhere" } })
  test("...or on one member by hash when no owner is a member", #d2.addrs == 1)
  eq("anything else goes to one member", 1, #placement.targets("weird/thing", MEMBERS).addrs)
  local one = placement.targets("job-1/x", { "solo" })
  test("a pool of one holds a job- key once", #one.addrs == 1 and one.need == 1)
  local _, none = placement.targets("job-1/x", {})
  eq("no members is no storage node", "no_storage_node", none)

  -- Spread, and HRW's promise: a member joining moves ONLY the keys it now
  -- ranks for. hash % N would reshuffle almost everything.
  local FOUR = { "m-1", "m-2", "m-3", "m-4" }
  local FIVE = { "m-1", "m-2", "m-3", "m-4", "m-5" }
  local count, moved, strays = {}, 0, 0
  local N = 400
  for i = 1, N do
    local k = "job-" .. i .. "/tasks/assignment-1"
    local before = placement.targets(k, FOUR).addrs
    local after = placement.targets(k, FIVE).addrs
    for _, x in ipairs(before) do count[x] = (count[x] or 0) + 1 end
    local same = (before[1] == after[1] and before[2] == after[2])
      or (before[1] == after[2] and before[2] == after[1])
    if not same then
      moved = moved + 1
      if after[1] ~= "m-5" and after[2] ~= "m-5" then strays = strays + 1 end
    end
  end
  local lo, hi = math.huge, 0
  for _, x in ipairs(FOUR) do lo = math.min(lo, count[x] or 0); hi = math.max(hi, count[x] or 0) end
  test("keys spread over the members (each holds 35-65% of 400 two-copy keys)",
    lo >= N * 2 / 4 * 0.7 and hi <= N * 2 / 4 * 1.3, lo .. ".." .. hi)
  eq("a member joining moves no key it does not now hold", 0, strays)
  test("...and moves about its share (2 of 5), not most of them",
    moved > N * 0.25 and moved < N * 0.55, moved)
end

print()
print("=== job- keys: two replicas, or none ===")
do
  local air, master, nodes = pool3()
  local client = freshClient(master.net, MEMBERS)
  test("the client sees a pool", client.isPool())
  eq("...of three", 3, #client.members())

  local key, plan = jobKeyWith("node-aaaa", true)
  local ack, err = client.put(key, "the task list", { ttl = 600 })
  test("a job- write is acknowledged", ack ~= nil, err)
  eq("...by two members", 2, ack and ack.replicas)
  test("...the two placement names", ack and ack.members[1] == plan.addrs[1] and ack.members[2] == plan.addrs[2])
  test("...each with its own lease", ack and ack.leases[plan.addrs[1]] ~= nil and ack.leases[plan.addrs[2]] ~= nil)
  local third
  for _, a in ipairs(MEMBERS) do if a ~= plan.addrs[1] and a ~= plan.addrs[2] then third = a end end
  test("both replicas hold it", nodes[plan.addrs[1]].store.exists(key) and nodes[plan.addrs[2]].store.exists(key))
  test("the third member does not", not nodes[third].store.exists(key))

  -- An OpenOS-style worker reads either replica over raw framing.
  local worker = newMachine(air, "worker-0001")
  worker.modem.open(2100)
  local got = {}
  worker.event.on("modem_message", function(_, _, from, port, _, data)
    if port == 2100 and type(data) == "string" then got[from] = serialize.decode(data) end
  end)
  for i, a in ipairs(plan.addrs) do
    worker.modem.send(a, 2100, serialize.encode({ magic = "PUB", op = "GET", key = key, req_id = i }))
  end
  test("a reader gets it from either replica",
    got[plan.addrs[1]] and got[plan.addrs[1]].data == "the task list"
    and got[plan.addrs[2]] and got[plan.addrs[2]].data == "the task list")

  local n, fails = client.releaseAll(key, ack.leases)
  eq("releaseAll releases it on both members", 2, n)
  eq("...with no failures", 0, #fails)
  test("...and neither holds it now", not nodes[plan.addrs[1]].store.exists(key)
    and not nodes[plan.addrs[2]].store.exists(key))

  -- A lease is good only where it was issued (answer 4).
  local ack2 = client.put(key, "again")
  local wrong = {}
  wrong[ack2.members[1]] = ack2.leases[ack2.members[2]]
  wrong[ack2.members[2]] = ack2.leases[ack2.members[1]]
  local same = ack2.leases[ack2.members[1]] == ack2.leases[ack2.members[2]]
  if not same then
    local n2 = client.releaseAll(key, wrong)
    eq("one member's lease does not release another's copy", 0, n2)
  else
    test("one member's lease does not release another's copy (leases collided; skipped)", true)
  end

  -- One replica down: the write is short, so it is released where it
  -- landed and the caller stays inline.
  local key3, plan3 = jobKeyWith("node-bbbb", true)
  down(air, "node-bbbb")
  local other = plan3.addrs[1] == "node-bbbb" and plan3.addrs[2] or plan3.addrs[1]
  local short, why = client.put(key3, "short of a replica")
  eq("a job- write that reaches one of two members fails", nil, short)
  test("...as replicas_short, 1 of 2", has(why, "replicas_short: 1 of 2"), why)
  test("...naming the member that did not answer", has(why, "node-bbb") and has(why, "timeout"), why)
  test("...and the lone copy is released, not left to its TTL", not nodes[other].store.exists(key3))
  local keyOk = jobKeyWith("node-bbbb", false)
  test("a key whose two members are both up still goes out", client.put(keyOk, "fine") ~= nil)
  up(air, "node-bbbb")
end

print()
print("=== shared/: a majority, versions, and repair ===")
do
  local air, master, nodes = pool3()
  local state = { _data = {} }
  local client = freshClient(master.net, MEMBERS, state)

  local ack = client.put("shared/config", "v1")
  test("a shared/ write is acknowledged", ack ~= nil)
  eq("...by every member", 3, ack and ack.replicas)
  local v = nodes["node-aaaa"].store.versionOf("shared/config")
  test("...carrying a version", v ~= nil and v.n == 1 and v.writer == "master-0001",
    v and (v.n .. "/" .. v.writer))

  down(air, "node-cccc")
  local ack2, err2 = client.put("shared/config", "v2")
  test("with one member of three down, it still stands", ack2 ~= nil, err2)
  eq("...on two", 2, ack2 and ack2.replicas)
  test("...naming the one that missed it", ack2 and ack2.missed and ack2.missed[1] == "node-cccc")
  eq("the version moved on", 2, nodes["node-aaaa"].store.versionOf("shared/config").n)

  down(air, "node-bbbb")
  local ack3, err3 = client.put("shared/config", "v3")
  eq("with two of three down there is no majority", nil, ack3)
  test("...and it says so", has(err3, "no_quorum: 1 of 2"), err3)
  up(air, "node-bbbb")
  up(air, "node-cccc")

  -- The returning members catch up.
  test("before repair the returned member holds the old copy",
    nodes["node-cccc"].store.versionOf("shared/config").n == 1)
  local r = client.repair()
  eq("repair sends what each member lacks", 2, r.repaired)
  eq("...with nothing failing", 0, r.failed)
  for _, a in ipairs(MEMBERS) do
    local data = nodes[a].store.get("shared/config")
    eq("after repair " .. a .. " holds the newest value", "v3", data)
  end
  local again = client.repair()
  eq("a second repair has nothing to send", 0, again.repaired)

  -- The node is the one that decides: an older version is refused there.
  local d = nodes["node-aaaa"]
  local stale, serr = d.store.put("shared/config", "old", { version = { n = 1, writer = "master-0001" } })
  eq("a member refuses an older version", nil, stale)
  test("...as stale_version", has(serr, "stale_version: have 3"), serr)
  local same = d.store.put("shared/config", "v3", { version = { n = 3, writer = "master-0001" } })
  test("...and takes the same version again as a repeat, changing nothing",
    same and same.unchanged == true and d.store.get("shared/config") == "v3")
  local rival = d.store.put("shared/config", "rival", { version = { n = 3, writer = "zz-other" } })
  test("a tie on the counter goes to the higher writer", rival ~= nil and d.store.get("shared/config") == "rival")
  d.store.put("shared/config", "v3", { version = { n = 4, writer = "master-0001" } })

  -- A Master whose record was lost starts its counter at 1 and would be
  -- refused forever. It steps past what the members hold instead.
  local fresh = freshClient(master.net, MEMBERS, { _data = {} })
  local ack4, err4 = fresh.put("shared/config", "after a lost state")
  test("a Master with no record still gets a shared/ write through", ack4 ~= nil, err4)
  test("...above the version the members held",
    nodes["node-bbbb"].store.versionOf("shared/config").n >= 5,
    nodes["node-bbbb"].store.versionOf("shared/config").n)

  -- dropShared removes it everywhere and stops repairing it.
  local n = fresh.dropShared("shared/config")
  eq("dropShared releases it on every member", 3, n)
  eq("...and repair no longer offers it", 0, fresh.repair().repaired)
end

print()
print("=== a LIST names who did not answer ===")
do
  local air, master, nodes = pool3()
  local client = freshClient(master.net, MEMBERS)
  local k1 = jobKeyWith("node-cccc", true)
  local k2 = jobKeyWith("node-cccc", false)
  client.put(k1, "one"); client.put(k2, "two")

  local all = client.list("job-9/")
  test("with every member up the list is whole", all and all.incomplete == false)
  eq("...holding each key once", 2, all and #all.keys)
  eq("...from both of its holders", 2, all and all.keys[1] and #all.keys[1].holders)

  down(air, "node-cccc")
  local part = client.list("job-9/")
  test("with a member down the list says it is incomplete", part and part.incomplete == true)
  test("...and names that member", part and part.missing[1] == "node-cccc")
  eq("...still listing what the others hold", 2, part and #part.keys)
  up(air, "node-cccc")
end

print()
print("=== one node, as before ===")
do
  local air = newAir()
  local master = newMachine(air, "master-0001")
  local n = bringUp(air, "node-0001", "master-0001")
  local client = freshClient(master.net, nil, { _data = { storage_node = { address = "node-0001" } } })
  test("no pool configured is not a pool", not client.isPool())
  local ack = client.put("job-2/tasks/assignment-1", "x")
  test("a job- write to one node needs one copy", ack ~= nil and ack.replicas == 1)
  test("...and release(key, lease) still works", client.release("job-2/tasks/assignment-1", ack.lease_id) ~= nil)
  down(air, "node-0001")
  local _, err = client.put("job-2/tasks/assignment-2", "x")
  eq("...and a node that is down still says timeout, as it always did", "timeout", err)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
return true
