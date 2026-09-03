-- ╔══════════════════════════════════════════════════════════╗
-- ║  Unit Test: kernel.netfs — remote filesystem shares       ║
-- ║                                                            ║
-- ║  Drives the REAL client proxy against the REAL server      ║
-- ║  dispatcher through an in-process loopback transport, on   ║
-- ║  top of a RAM filesystem. No network, but every byte still ║
-- ║  goes proxy → op → confinement → fs and back.              ║
-- ║                                                            ║
-- ║  The three things worth breaking a build over:             ║
-- ║   1. Confinement. `..` must not climb out of an export.    ║
-- ║   2. Fail-closed. No allow entry, no access; ro means ro.  ║
-- ║   3. The component handle contract — open() returns an      ║
-- ║      OPAQUE handle and read/write take it as an argument,   ║
-- ║      because jbod and fs both drive members that way. A     ║
-- ║      method-bearing handle here is the same mismatch that   ║
-- ║      hid the jbod routing bug.                              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_netfs.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_netfs.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

local _uptime = 0
package.loaded["computer"] = { uptime = function() return _uptime end }
package.loaded["kernel.serialize"] = tryload("tos/kernel/serialize.lua")()

local netfs = tryload("tos/kernel/netfs.lua")()

-- ── A RAM filesystem standing in for kernel.fs ──────────────────────
-- normalize is the real algorithm, because _confine's whole defence
-- rests on `..` actually being resolved rather than pattern-matched.
local function ramFS()
  local files, dirs = {}, { ["/"] = true }
  local F = {}
  function F.normalize(p)
    if type(p) ~= "string" then return nil end
    local parts = {}
    for seg in p:gmatch("[^/]+") do
      if seg == ".." then
        if #parts > 0 then table.remove(parts) end
      elseif seg ~= "." then
        parts[#parts + 1] = seg
      end
    end
    return "/" .. table.concat(parts, "/")
  end
  function F.exists(p) return files[p] ~= nil or dirs[p] == true end
  function F.isDirectory(p) return dirs[p] == true end
  function F.size(p) return files[p] and #files[p] or 0 end
  function F.lastModified(p) return files[p] and 7 or 0 end
  function F.spaceTotal() return 10000 end
  function F.spaceUsed() local u = 0; for _, v in pairs(files) do u = u + #v end; return u end
  function F.makeDirectory(p) dirs[p] = true; return true end
  function F.remove(p)
    local had = files[p] ~= nil or dirs[p] ~= nil
    files[p] = nil; dirs[p] = nil; return had
  end
  function F.rename(a, b)
    if files[a] == nil then return false end
    files[b] = files[a]; files[a] = nil; return true
  end
  function F.list(p)
    local out = {}
    local prefix = p == "/" and "/" or (p .. "/")
    for k in pairs(files) do
      if k:sub(1, #prefix) == prefix then
        local rest = k:sub(#prefix + 1)
        if not rest:find("/") then out[#out + 1] = rest end
      end
    end
    table.sort(out)
    return out
  end
  function F.open(p, mode)
    mode = mode or "r"
    if mode:find("[wa]") then
      if mode:find("w") then files[p] = "" end
      files[p] = files[p] or ""
    elseif files[p] == nil then
      return nil, "not found"
    end
    local pos = 1
    return {
      read = function(self, n)
        local d = files[p] or ""
        if pos > #d then return nil end
        local c = d:sub(pos, pos + n - 1); pos = pos + #c; return c
      end,
      write = function(self, x) files[p] = (files[p] or "") .. x; return true end,
      close = function(self) return true end,
      seek  = function(self, whence, off) pos = (tonumber(off) or 0) + 1; return pos - 1 end,
    }
  end
  F._files, F._dirs = files, dirs
  return F
end

-- ── Wiring ──────────────────────────────────────────────────────────
local PEER, STRANGER = "peer-aaaa", "peer-zzzz"
local FS = ramFS()
netfs.init({
  fs = FS,
  computer = package.loaded["computer"],
  trust = { LEVEL = { TRUSTED = 3 }, getLevel = function(a)
    return a == PEER and 3 or 0 end },
  -- no net: init must not explode without one, and the loopback
  -- transport below bypasses the wire entirely.
})

FS.makeDirectory("/srv")
FS.makeDirectory("/srv/pub")
FS._files["/srv/pub/hello.txt"] = "hello world"
FS._files["/srv/pub/big.bin"]   = string.rep("A", 10000)  -- > 2 blocks
FS._files["/secret.txt"]        = "do not serve this"
FS.makeDirectory("/srv/public-extra")
FS._files["/srv/public-extra/leak.txt"] = "adjacent prefix"

local ok, err = netfs.setExports(netfs._validateExports({
  { name = "pub",   path = "/srv/pub",  mode = "rw", allow = { PEER } },
  { name = "ropub", path = "/srv/pub",  mode = "ro", allow = { PEER } },
  { name = "nobody", path = "/srv/pub", mode = "rw", allow = {} },
}))

-- Loopback: the client's rpc call goes straight into the server
-- dispatcher as `from`. Bypasses trust/verify (those are handleRequest's
-- job and are tested separately below) but exercises everything else.
local function loopback(fromAddr)
  return function(op, payload) return netfs._dispatch(op, payload, fromAddr) end
end

print("=== netfs Tests ===")
print()

-- ── 1. Export validation ────────────────────────────────────────────
print("-- export validation --")
do
  local list, e = netfs._validateExports({ { name = "a", path = "/srv/pub" } })
  test("minimal export validates", "table", type(list))
  test("...defaults to read-only", "ro", list and list[1].mode)

  local _, e1 = netfs._validateExports({ { name = "bad name", path = "/x" } })
  test("rejects a spacey name", "invalid_export", e1 and e1:match("^[a-z_]+"))
  local _, e2 = netfs._validateExports({ { name = "a", path = "/x", mode = "rwx" } })
  test("rejects a bogus mode", true, e2 ~= nil)
  local _, e3 = netfs._validateExports({ { name = "a", path = "/x" }, { name = "a", path = "/y" } })
  test("rejects duplicate names", true, e3 ~= nil)
  local _, e4 = netfs._validateExports({ { name = "a", path = "/" } })
  test("refuses to export /", true, e4 ~= nil and e4:find("refuses") ~= nil)
  -- A trailing slash must not survive into the confinement prefix.
  local l5 = netfs._validateExports({ { name = "a", path = "/srv/pub/" } })
  test("normalizes a trailing slash", "/srv/pub", l5 and l5[1].path)
end

-- ── 2. Confinement — the security boundary ──────────────────────────
print()
print("-- confinement --")
do
  local e = netfs._findExport("pub")
  test("plain path resolves", "/srv/pub/hello.txt", (netfs._confine(e, "/hello.txt")))
  test("bare relative resolves", "/srv/pub/hello.txt", (netfs._confine(e, "hello.txt")))
  test("root of share resolves", "/srv/pub", (netfs._confine(e, "/")))

  -- Traversal, in the forms people actually try.
  test("rejects ../",        nil, (netfs._confine(e, "/../secret.txt")))
  test("rejects deep ../",   nil, (netfs._confine(e, "/a/b/../../../secret.txt")))
  test("rejects bare ..",    nil, (netfs._confine(e, "..")))
  -- The adjacent-prefix trap: /srv/pub must not grant /srv/public-extra.
  test("rejects sibling prefix", nil, (netfs._confine(e, "/../public-extra/leak.txt")))
  -- Absurd lengths are refused before any filesystem work happens.
  test("rejects an overlong path", nil, (netfs._confine(e, "/" .. string.rep("x", 400))))
end

-- ── 3. Access control ───────────────────────────────────────────────
print()
print("-- access control --")
do
  local pub = netfs._findExport("pub")
  test("allowed peer, read",  true,  (netfs._accessOk(pub, PEER, false)))
  test("allowed peer, write", true,  (netfs._accessOk(pub, PEER, true)))
  test("stranger refused",    false, (netfs._accessOk(pub, STRANGER, false)))
  local _, why = netfs._accessOk(pub, STRANGER, false)
  test("...as not_allowed",   "not_allowed", why)

  local ro = netfs._findExport("ropub")
  test("ro export allows read",  true,  (netfs._accessOk(ro, PEER, false)))
  test("ro export denies write", false, (netfs._accessOk(ro, PEER, true)))
  local _, rwhy = netfs._accessOk(ro, PEER, true)
  test("...as read_only_export", "read_only_export", rwhy)

  -- An export with an empty allow list is a misconfiguration, and the
  -- safe reading of a missing rule is "no".
  local nb = netfs._findExport("nobody")
  test("empty allow denies everyone", false, (netfs._accessOk(nb, PEER, false)))

  test("unknown export refused", false, (netfs._accessOk(nil, PEER, false)))
  local _, uwhy = netfs._accessOk(nil, PEER, false)
  test("...as no_such_export", "no_such_export", uwhy)
end

-- ── 4. The client proxy, end to end ─────────────────────────────────
print()
print("-- proxy round trip --")
do
  local px = netfs.attach("host", "pub", { transport = loopback(PEER) })

  test("exists finds a served file", true,  px.exists("/hello.txt"))
  test("exists misses an absent one", false, px.exists("/nope.txt"))
  test("exists cannot see outside",  false, px.exists("/../secret.txt"))
  test("size reports through",        11,    px.size("/hello.txt"))
  test("isDirectory on a file",       false, px.isDirectory("/hello.txt"))
  test("spaceTotal reports through",  10000, px.spaceTotal())
  test("rw export is not read-only",  false, px.isReadOnly())

  local names = {}
  for _, n in ipairs(px.list("/")) do names[n] = true end
  test("list sees hello.txt", true, names["hello.txt"] == true)
  test("list sees big.bin",   true, names["big.bin"] == true)
end

-- ── 5. Handles are component-style ──────────────────────────────────
-- This is the contract jbod.makePool and kernel/fs.lua both require.
print()
print("-- component handle contract --")
do
  local px = netfs.attach("host", "pub", { transport = loopback(PEER) })

  local h = px.open("/hello.txt", "r")
  test("open returns an opaque handle", "number", type(h))
  test("...not a method-bearing table", false, type(h) == "table")
  local chunk = px.read(h, 5)
  test("proxy.read(handle, n) works", "hello", chunk)
  test("...and advances", " worl", px.read(h, 5))
  px.close(h)

  -- Reads spanning several network blocks must reassemble exactly.
  local h2 = px.open("/big.bin", "r")
  local got, part = "", nil
  repeat
    part = px.read(h2, 4096)
    if part then got = got .. part end
  until not part
  px.close(h2)
  test("multi-block read is complete", 10000, #got)
  test("...and not corrupted", true, got == string.rep("A", 10000))

  -- Writes buffer and flush on close.
  local wh = px.open("/written.txt", "w")
  px.write(wh, "alpha ")
  px.write(wh, "beta")
  -- Buffered: 10 bytes is under BLOCK, so nothing has crossed the wire
  -- yet. open("w") truncated the file server-side, so it exists and is
  -- empty — that distinction is the point, and it is why the write
  -- being non-durable until close() is documented rather than implied.
  test("open(w) truncated server-side", "", FS._files["/srv/pub/written.txt"])
  px.close(wh)
  test("write lands after close", "alpha beta", FS._files["/srv/pub/written.txt"])

  -- A write larger than one block still arrives intact.
  local bh = px.open("/large.txt", "w")
  px.write(bh, string.rep("Q", 9000))
  px.close(bh)
  test("multi-block write is complete", 9000, #(FS._files["/srv/pub/large.txt"] or ""))
end

-- ── 6. Writes through a read-only export ────────────────────────────
print()
print("-- read-only enforcement --")
do
  local ro = netfs.attach("host", "ropub", { transport = loopback(PEER) })
  test("ro export reports read-only", true, ro.isReadOnly())
  local h, err = ro.open("/blocked.txt", "w")
  test("open for write refused", nil, h)
  test("...as read_only_export", "read_only_export", err)
  test("...and nothing was created", nil, FS._files["/srv/pub/blocked.txt"])
  test("ro export still reads", true, ro.exists("/hello.txt"))
  test("remove refused on ro", false, ro.remove("/hello.txt"))
  test("...file survives", "hello world", FS._files["/srv/pub/hello.txt"])
end

-- ── 7. A stranger gets nothing ──────────────────────────────────────
print()
print("-- stranger --")
do
  local sx = netfs.attach("host", "pub", { transport = loopback(STRANGER) })
  test("stranger cannot stat",  false, sx.exists("/hello.txt"))
  test("stranger lists nothing", 0,    #sx.list("/"))
  test("stranger cannot open",  nil,   sx.open("/hello.txt", "r"))
  test("stranger cannot write", nil,   sx.open("/x.txt", "w"))
end

-- ── 8. Handle scoping and limits ────────────────────────────────────
print()
print("-- handle hygiene --")
do
  netfs._internal.resetHandles()
  local a = netfs.attach("host", "pub", { transport = loopback(PEER) })
  local ha = a.open("/hello.txt", "r")
  test("peer opened a handle", "number", type(ha))

  -- A different peer must not be able to touch it by guessing the id.
  -- Handles are keyed by address, so the forged id resolves to nothing.
  local stolen = netfs._dispatch("read", { handle_id = 1, n = 5 }, STRANGER)
  test("another peer cannot read the handle", "no_such_handle", stolen.err)

  -- The per-peer cap stops a handle table becoming a memory target.
  local opened = 0
  for _ = 1, netfs._internal.MAX_HANDLES + 4 do
    if a.open("/hello.txt", "r") then opened = opened + 1 end
  end
  test("open is capped per peer", true, opened < netfs._internal.MAX_HANDLES + 4)
  local over = netfs._dispatch("open",
    { share = "pub", path = "/hello.txt", mode = "r" }, PEER)
  test("...and says why", "too_many_handles", over.err)

  -- Idle handles are reaped, so an abandoned session doesn't pin them.
  _uptime = _uptime + netfs._internal.HANDLE_IDLE + 1
  netfs._dispatch("stat", { share = "pub", path = "/hello.txt" }, PEER)
  local live = 0
  for _, t in pairs(netfs._internal.handles()) do
    for _ in pairs(t) do live = live + 1 end
  end
  test("idle handles are reaped", 0, live)
end

-- ── 9. Server-side op hygiene ───────────────────────────────────────
print()
print("-- dispatcher --")
do
  netfs._internal.resetHandles()
  test("unknown op refused", "unknown_op",
    netfs._dispatch("wat", { share = "pub" }, PEER).err)
  test("unknown share refused", "no_such_export",
    netfs._dispatch("stat", { share = "ghost", path = "/x" }, PEER).err)
  -- A peer must not be able to size the server's read.
  local h = netfs._dispatch("open", { share = "pub", path = "/big.bin", mode = "r" }, PEER)
  local big = netfs._dispatch("read",
    { handle_id = h.handle_id, n = 999999 }, PEER)
  test("read is clamped to one block", true,
    big.data ~= nil and #big.data <= netfs._internal.BLOCK)
  -- close is idempotent: a retried close must not error.
  netfs._dispatch("close", { handle_id = h.handle_id }, PEER)
  test("close is idempotent", true,
    netfs._dispatch("close", { handle_id = h.handle_id }, PEER).ok)
  -- rename must confine BOTH ends, or it writes anywhere on the host.
  local rn = netfs._dispatch("rename",
    { share = "pub", path = "/hello.txt", to = "/../escaped.txt" }, PEER)
  test("rename confines its destination", "invalid_path", rn.err)
  test("...and nothing escaped", nil, FS._files["/escaped.txt"])
end

-- ── 10. Fail-closed serving ─────────────────────────────────────────
-- handleRequest is the only network entry point, and it must refuse
-- everything while the netfsd service has not armed it.
print()
print("-- fail-closed --")
do
  local sent = {}
  local fakeProto = {
    TYPE = { NETFS_REQ = "nfs_req", NETFS_RES = "nfs_res" },
    makePacket = function(t, p) return { type = t, payload = p } end,
  }
  local fakeNet = {
    on = function() return 1 end,
    send = function(_, pkt) sent[#sent + 1] = pkt; return true end,
    verifyPeer = function() return true end,
    getProtocol = function() return fakeProto end,
  }
  netfs.init({
    fs = FS, computer = package.loaded["computer"], net = fakeNet,
    protocol = fakeProto,
    trust = { LEVEL = { TRUSTED = 3 },
              getLevel = function(a) return a == PEER and 3 or 0 end },
  })

  test("starts disarmed", false, netfs.isEnabled())
  netfs.handleRequest({ payload = { op = "stat", share = "pub", path = "/hello.txt" } }, PEER)
  test("disarmed serves nothing", 0, #sent)

  netfs.setEnabled(true)
  netfs.handleRequest({ payload = { op = "stat", share = "pub", path = "/hello.txt" } }, PEER)
  test("armed answers a trusted peer", 1, #sent)
  test("...with the real result", true, sent[1].payload.exists)

  -- A non-trusted peer gets a deliberately uninformative denial: it must
  -- not be able to tell trust from verification from a missing file.
  netfs.handleRequest({ payload = { op = "stat", share = "pub", path = "/hello.txt" } },
    STRANGER)
  test("stranger is denied", "denied", sent[2] and sent[2].payload.err)
  test("...and learns nothing else", nil, sent[2] and sent[2].payload.exists)

  netfs.setEnabled(false)
  test("disarms again", false, netfs.isEnabled())
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
