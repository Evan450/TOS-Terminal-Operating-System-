-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: cluster-storaged — the Storage Node daemon's wiring     ║
-- ║                                                              ║
-- ║  store.lua has its own test (test_store.lua); this is the      ║
-- ║  daemon's seam -- the §4.6 namespace authorization that gates   ║
-- ║  every write op, the write-plane handlers (PUT/EXTEND/RELEASE/   ║
-- ║  LIST), and the §3.2 unauthenticated read plane -- against the    ║
-- ║  REAL kernel.net.protocol (TOS-Dev) and cluster.protocol           ║
-- ║  (manager-skeleton) rather than a duplicated fake of either, so     ║
-- ║  this exercises the actual canWrite/validatePubRequest rules the     ║
-- ║  spec's §4.6 "shared, not reimplemented" design depends on.           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua cluster/storage-skeleton/test_storaged.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local ROOT = "cluster/storage-skeleton/"
local DEV  = "../TOS-Dev/"

local function fsStub()
  local files, dirs = {}, {}
  return {
    makeDirectory = function(p) dirs[p] = true; return true end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, d) files[p] = d; return true end,
    remove = function(p) files[p] = nil; return true end,
    rename = function(a, b)
      if files[a] == nil then return false, "no such file" end
      files[b] = files[a]; files[a] = nil; return true
    end,
    -- store.capacity() asks this when the config's own `capacity` is 0
    -- ("ask the filesystem"), which cluster-storage.cfg's own DEFAULTS
    -- leaves it at. Without this every put refused as out_of_space,
    -- free always 0.
    spaceTotal = function() return 1024 * 1024 end,
  }, files
end

local function fakeNet()
  local handlers, sent = {}, {}
  local net = {
    on  = function(kind, fn) handlers[kind] = fn; return kind end,
    off = function(kind, id) handlers[kind] = nil end,
    send = function(to, packet, port) sent[#sent + 1] = { to = to, packet = packet, port = port } end,
    --! No sendRaw, on purpose: kernel.net has none. A fake that offered one
    --! is how the read plane shipped answering through a call that did not
    --! exist; replies now travel through the injected `rawSend` below.
  }
  return net, handlers, sent
end

-- A fresh daemon instance per test, the same loadfile-not-require
-- technique the rest of this suite uses for module-level state: both
-- storaged.lua and store.lua keep theirs in locals, so a real require()
-- would hand every test the same, already-started daemon.
local function freshStoraged(deps)
  local env
  local function req(name)
    if name == "computer" then return deps.computer end
    if name == "kernel.fs" then return deps.fs end
    if name == "kernel.serialize" then return deps.serialize end
    if name == "cluster.store" then return deps.store end
    error("sandbox: module '" .. name .. "' not stubbed for this test", 2)
  end
  env = setmetatable({ require = req }, { __index = _G })
  return assert(loadfile(ROOT .. "usr/lib/cluster-storaged.lua", "t", env))()
end

local function freshStore()
  local chunk = assert(loadfile(ROOT .. "usr/lib/cluster/store.lua"))
  return chunk()
end

local serialize = assert(loadfile(DEV .. "tos/kernel/serialize.lua"))()
local cproto = assert(loadfile(ROOT .. "../manager-skeleton/usr/lib/cluster/protocol.lua"))()

-- kernel.net.protocol needs "computer" and "kernel.serialize" at load time.
local function freshProtocol(computer)
  local env = setmetatable({ require = function(n)
    if n == "computer" then return computer end
    if n == "kernel.serialize" then return serialize end
    error("sandbox: module '" .. n .. "' not stubbed", 2)
  end }, { __index = _G })
  return assert(loadfile(DEV .. "tos/kernel/net/protocol.lua", "t", env))()
end

-- Clears rig.sent IN PLACE. "rig.sent = {}" would only repoint the
-- table my test code holds -- the fake net's send/sendRaw closures
-- captured the ORIGINAL table as an upvalue and would keep appending to
-- that one forever, so every "after clearing" assertion would read an
-- empty table that nothing was ever filling.
local function clearSent(rig)
  for i = #rig.sent, 1, -1 do rig.sent[i] = nil end
end

local function clockOf(t0)
  local t = t0 or 0
  return { uptime = function() return t end }, function(d) t = t + d end
end

print("=== cluster-storaged Tests ===")
print()

local function newRig(cfgOverrides)
  local computer, advance = clockOf()
  local fs = fsStub()
  local protocol = freshProtocol(computer)
  local net, handlers, sent = fakeNet()
  local function rawSend(via, to, port, blob)
    sent[#sent + 1] = { to = to, port = port, raw = blob, via = via }
  end
  local storaged = freshStoraged({
    computer = computer, fs = fs, serialize = serialize, store = freshStore(),
  })
  storaged._internal.setConfig(nil)   -- force loadConfig to run fresh inside start()
  local okStart, serr = storaged.start({
    net = net, cproto = cproto, protocol = protocol, modems = {},
    rawSend = rawSend,
    config_path = "/etc/cluster-storage.cfg",
  })
  if cfgOverrides then
    for k, v in pairs(cfgOverrides) do storaged.config()[k] = v end
  end
  return storaged, { net = net, handlers = handlers, sent = sent, protocol = protocol, computer = computer, advance = advance }
end

-- ── Lifecycle: start wires the write-plane handlers ─────────────────
do
  local storaged, rig = newRig()
  test("start succeeds with net+cproto+protocol present", storaged.isRunning())
  local T = rig.protocol.TYPE
  test("STORE_PUT handler registered", rig.handlers[T.STORE_PUT] ~= nil)
  test("STORE_LEASE_EXTEND handler registered", rig.handlers[T.STORE_LEASE_EXTEND] ~= nil)
  test("STORE_RELEASE handler registered", rig.handlers[T.STORE_RELEASE] ~= nil)
  test("STORE_LIST handler registered", rig.handlers[T.STORE_LIST] ~= nil)
  storaged.stop()
  test("stop unregisters (isRunning now false)", not storaged.isRunning())
end

do
  local storaged = freshStoraged({ computer = clockOf(), fs = fsStub(), serialize = serialize, store = freshStore() })
  -- cproto passed explicitly: start()'s own cproto lookup is a bare
  -- require with no firstRequire fallback, unlike net/protocol, so
  -- leaving it out here would test THAT inconsistency instead of the
  -- "no network hardware" path this block means to exercise.
  local ok, err = storaged.start({ cproto = cproto })   -- no net, no protocol
  test("start refuses cleanly with no network", not ok)
  eq("...naming the reason", "no_network", err)
end

-- ── writerFor (§4.6 identity resolution) ────────────────────────────
do
  local storaged, rig = newRig({ master = "master-addr", managers = { ["mgr-1"] = 3 } })
  local w = storaged.writerFor("master-addr")
  eq("the configured master resolves to role=master", "master", w and w.role)
  local w2 = storaged.writerFor("mgr-1")
  eq("a configured manager resolves to role=manager", "manager", w2 and w2.role)
  eq("...with its domain_id", 3, w2 and w2.domain_id)
  local w3, e3 = storaged.writerFor("stranger")
  test("an unconfigured address resolves to nothing", w3 == nil)
  eq("...explained as unknown_writer", "unknown_writer", e3)
end

-- ── _onPut: authorization gate, then the real store ─────────────────
do
  local storaged, rig = newRig({ master = "master-addr", managers = { ["mgr-3"] = 3 } })
  local T = rig.protocol.TYPE

  -- The Master may write shared/.
  storaged._onPut({ payload = { key = "shared/manifest", data = "hello" } }, "master-addr")
  local ack = rig.sent[#rig.sent]
  eq("master PUT to shared/ is acknowledged", T.STORE_PUT_ACK, ack.packet.type)
  eq("the key round-trips", "shared/manifest", ack.packet.payload.key)

  -- A Manager may NOT write shared/.
  clearSent(rig)
  storaged._onPut({ payload = { key = "shared/x", data = "nope" } }, "mgr-3")
  local err = rig.sent[#rig.sent]
  eq("a manager's PUT to shared/ is refused", T.STORE_ERROR, err.packet.type)
  test("...for a namespace reason, not a storage one",
    err.packet.payload.reason:find("namespace_denied", 1, true) ~= nil)

  -- The owning Manager MAY write its own domain-<id>/.
  storaged._onPut({ payload = { key = "domain-3/scratch/a", data = "mine" } }, "mgr-3")
  local ok2 = rig.sent[#rig.sent]
  eq("the owning manager's PUT to its own domain succeeds", T.STORE_PUT_ACK, ok2.packet.type)

  -- A DIFFERENT manager may not write domain-3/.
  storaged._onPut({ payload = { key = "domain-3/scratch/b", data = "intruder" } }, "unknown-addr")
  local denied = rig.sent[#rig.sent]
  eq("an unconfigured writer is refused before the namespace check even runs",
    T.STORE_ERROR, denied.packet.type)

  -- A missing key is refused before authorization is even attempted.
  storaged._onPut({ payload = { data = "x" } }, "master-addr")
  local badKey = rig.sent[#rig.sent]
  eq("a PUT with no key is refused", T.STORE_ERROR, badKey.packet.type)
end

-- ── _onExtend / _onRelease go through the same authorize() gate ────
do
  local storaged, rig = newRig({ master = "master-addr" })
  local T = rig.protocol.TYPE
  storaged._onPut({ payload = { key = "shared/x", data = "data" } }, "master-addr")
  local lease = rig.sent[#rig.sent].packet.payload.lease_id

  storaged._onExtend({ payload = { key = "shared/x", lease_id = lease, extend_by = 10 } }, "master-addr")
  test("extend by the authorized writer succeeds",
    rig.sent[#rig.sent].packet.type == T.STORE_PUT_ACK)

  storaged._onExtend({ payload = { key = "shared/x", lease_id = lease } }, "some-manager")
  eq("extend by an unauthorized writer is refused (even with the right lease)",
    T.STORE_ERROR, rig.sent[#rig.sent].packet.type)

  storaged._onRelease({ payload = { key = "shared/x", lease_id = lease } }, "master-addr")
  eq("release by the authorized writer succeeds", T.STORE_PUT_ACK, rig.sent[#rig.sent].packet.type)
end

-- ── _onList: no namespace gate at all (§4.6: everything readable) ──
do
  local storaged, rig = newRig({ master = "master-addr" })
  local T = rig.protocol.TYPE
  storaged._onPut({ payload = { key = "shared/a", data = "1" } }, "master-addr")
  storaged._onList({ payload = { prefix = "shared/" } }, "anyone-at-all")
  local res = rig.sent[#rig.sent]
  eq("LIST answers even an unconfigured address", T.STORE_LIST_RES, res.packet.type)
  eq("...and finds the key", 1, #res.packet.payload.keys)
end

-- ── _onPubMessage: the unauthenticated read plane (§3.2) ────────────
do
  local storaged, rig = newRig({ master = "master-addr" })
  storaged._onPut({ payload = { key = "shared/doc", data = "public data" } }, "master-addr")
  clearSent(rig)

  storaged._onPubMessage("rando-addr", serialize.encode({ magic = "PUB", op = "GET", key = "shared/doc", req_id = 1 }), "modem-0")
  local res = rig.sent[#rig.sent]
  test("an unauthenticated GET gets an answer", res ~= nil)
  eq("...addressed to the asker", "rando-addr", res and res.to)
  eq("...on the read port", 2100, res and res.port)
  eq("...out of the modem that heard it", "modem-0", res and res.via)
  eq("...with the right data", "public data", res.raw and serialize.decode(res.raw).data)

  clearSent(rig)
  storaged._onPubMessage("rando-addr", serialize.encode({ magic = "PUB", op = "LIST", prefix = "shared/", req_id = 2 }))
  local lres = rig.sent[#rig.sent]
  test("an unauthenticated LIST gets an answer", lres ~= nil)

  clearSent(rig)
  storaged._onPubMessage("rando-addr", "not even serialized data")
  eq("garbage input is silently dropped, not an error oracle", 0, #rig.sent)

  clearSent(rig)
  storaged._onPubMessage("rando-addr", serialize.encode({ magic = "WRONG", op = "GET", key = "shared/doc" }))
  eq("wrong magic is silently dropped too", 0, #rig.sent)
end

-- ── A PUT over the chunk threshold actually chunks the reply ───────
do
  local storaged, rig = newRig({ master = "master-addr" })
  local big = string.rep("x", 6144 * 2 + 100)   -- just over two chunks
  storaged._onPut({ payload = { key = "shared/big", data = big } }, "master-addr")
  clearSent(rig)
  storaged._onPubMessage("rando-addr", serialize.encode({ magic = "PUB", op = "GET", key = "shared/big", req_id = 9 }))
  test("a value over the chunk size is split into more than one reply", #rig.sent > 1)
  local total = 0
  local sawTotal
  for _, s in ipairs(rig.sent) do
    local msg = serialize.decode(s.raw)
    total = total + #(msg.data or "")
    sawTotal = msg.total
  end
  eq("every byte of the value is accounted for across the chunks", #big, total)
  eq("chunk count matches what was actually sent", #rig.sent, sawTotal)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
