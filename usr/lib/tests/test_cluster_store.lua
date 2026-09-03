-- ╔══════════════════════════════════════════════════════════╗
-- ║  Unit Test: cluster.store — Public storage tier            ║
-- ║                                                            ║
-- ║  The Storage Node's core, against a RAM filesystem: keys,  ║
-- ║  leases, TTL, eviction and the index.                      ║
-- ║                                                            ║
-- ║  Contract is the protocol spec: §4.5 operations, §5 TTL    ║
-- ║  and lease semantics, §5.1 eviction priority. Namespace    ║
-- ║  ACLs (§4.6) are NOT here — those are cluster.protocol's    ║
-- ║  canWrite, which the daemon calls before reaching store.   ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_store.lua

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

local _uptime = 0
local function clockAt(t) _uptime = t end
package.loaded["computer"] = { uptime = function() return _uptime end }

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

local store = loadRel("storage-skeleton/usr/lib/cluster/store.lua")
if not store then
  print("FAIL: could not load cluster.store")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- ── RAM filesystem ──────────────────────────────────────────────────
local function ramFS(total)
  local files, dirs = {}, {}
  local F = { _files = files, _dirs = dirs }
  function F.exists(p) return files[p] ~= nil or dirs[p] == true end
  function F.makeDirectory(p) dirs[p] = true; return true end
  function F.readFile(p) return files[p] end
  function F.writeFile(p, d) files[p] = d; return true end
  function F.remove(p)
    local had = files[p] ~= nil or dirs[p] ~= nil
    files[p] = nil; dirs[p] = nil; return had
  end
  function F.rename(a, b)
    if files[a] == nil then return false, "missing" end
    files[b] = files[a]; files[a] = nil; return true
  end
  function F.spaceTotal() return total end
  return F
end

local ser = {
  encode = function(t)
    -- Just enough round-tripping for the index.
    local parts = {}
    for k, v in pairs(t.index or {}) do
      parts[#parts + 1] = table.concat({ k, v.lease_id, v.expires_at,
        v.size, v.created, v.last_access }, "\1")
    end
    return (t.used or 0) .. "\2" .. table.concat(parts, "\n")
  end,
  decode = function(blob)
    local used, rest = blob:match("^(%-?%d+)\2(.*)$")
    if not used then return nil end
    local idx = {}
    for line in (rest or ""):gmatch("[^\n]+") do
      local k, l, e, s, c, a = line:match(
        "^([^\1]*)\1([^\1]*)\1([^\1]*)\1([^\1]*)\1([^\1]*)\1([^\1]*)$")
      if k then
        idx[k] = { lease_id = l, expires_at = tonumber(e), size = tonumber(s),
                   created = tonumber(c), last_access = tonumber(a) }
      end
    end
    return { index = idx, used = tonumber(used) }
  end,
}

-- Deterministic lease ids so assertions can name them.
local leaseN = 0
local function freshStore(total)
  leaseN = 0
  local FS = ramFS(total or 100000)
  store.init({ root = "/var/store", capacity = total or 100000,
    fs = FS, computer = package.loaded["computer"], serialize = ser,
    leaseFn = function() leaseN = leaseN + 1; return "L" .. leaseN end })
  return FS
end

print("=== cluster.store Tests ===")
print()

-- ── 1. Key validation (path safety) ─────────────────────────────────
print("-- key validation --")
do
  freshStore()
  test("accepts a job key",    "table", type(store.validateKey("job-17/tasks/a3")))
  test("accepts a domain key", "table", type(store.validateKey("domain-3/scratch/x")))
  test("accepts shared",       "table", type(store.validateKey("shared/manifest")))

  local function why(k) local _, e = store.validateKey(k); return e end
  test("rejects empty",            "invalid_key: empty",              why(""))
  test("rejects absolute",         "invalid_key: absolute",           why("/job-1/x"))
  test("rejects trailing slash",   "invalid_key: trailing separator", why("job-1/x/"))
  test("rejects empty segment",    "invalid_key: empty segment",      why("job-1//x"))
  test("rejects ..",               "invalid_key: relative segment",   why("job-1/../etc/passwd"))
  test("rejects a bare .",         "invalid_key: relative segment",   why("job-1/./x"))
  test("rejects one segment",      "invalid_key: needs <namespace>/<path>", why("lonely"))
  test("rejects an overlong key",  "invalid_key: too long",           why("job-1/" .. string.rep("x", 200)))
  -- Anything that could confuse a path is refused at the segment level.
  test("rejects a backslash",  true, why("job-1/a\\b") ~= nil)
  test("rejects a null-ish char", true, why("job-1/a b") ~= nil)

  -- The mapping is under the root, always.
  test("maps under the root", "/var/store/job-17/tasks/a3", (store.pathFor("job-17/tasks/a3")))
  test("bad key maps nowhere", nil, (store.pathFor("job-1/../x")))
end

-- ── 2. put / get (§4.5) ─────────────────────────────────────────────
print()
print("-- put / get --")
do
  local FS = freshStore()
  clockAt(100)
  local ack, err = store.put("job-1/tasks/a1", "hello")
  test("put succeeds",          "table", type(ack))
  test("...returns a lease",    "L1",    ack and ack.lease_id)
  test("...reports the size",   5,       ack and ack.size_bytes)
  test("...expires at +1h",     3700,    ack and ack.expires_at)
  test("...no error",           nil,     err)
  test("get returns the bytes", "hello", (store.get("job-1/tasks/a1")))
  test("exists agrees",         true,    store.exists("job-1/tasks/a1"))
  test("used tracks the size",  5,       store.used())
  -- The payload really is on disk under the mapped path.
  test("payload landed on disk", "hello", FS._files["/var/store/job-1/tasks/a1"])
  test("no temp file left",      nil,     FS._files["/var/store/job-1/tasks/a1.tmp"])

  test("get of a missing key",  "no_such_key", select(2, store.get("job-1/nope")))
  test("put rejects non-string", "invalid_data: not a string",
    select(2, store.put("job-1/x", 42)))

  -- overwrite = false is the §4.5 default-ish guard.
  local _, e2 = store.put("job-1/tasks/a1", "again", { overwrite = false })
  test("overwrite=false refuses", "exists: job-1/tasks/a1", e2)
  test("...original intact",      "hello", (store.get("job-1/tasks/a1")))

  local ack2 = store.put("job-1/tasks/a1", "replaced")
  test("overwrite by default",    "replaced", (store.get("job-1/tasks/a1")))
  test("...size accounting is a delta", 8, store.used())
  test("...a new lease is issued", "L2", ack2.lease_id)
end

-- ── 3. TTL and leases (§5) ──────────────────────────────────────────
print()
print("-- ttl and leases --")
do
  freshStore()
  clockAt(0)
  local ack = store.put("job-2/x", "d", { ttl = 60 })
  test("explicit ttl honoured", 60, ack.expires_at)

  -- A single lease window is capped at 24 h from now, but extensions
  -- are unlimited — the cap is per-window, not cumulative.
  local big = store.put("job-2/y", "d", { ttl = 999999 })
  test("single lease clamped to 24h", 86400, big.expires_at)

  clockAt(50)
  local ext, eerr = store.extend("job-2/x", "L1", 100)
  test("extend succeeds",      "table", type(ext))
  test("...from NOW, not from expiry", 150, ext and ext.expires_at)
  test("...no error",          nil,     eerr)

  test("extend needs the right lease", "lease_mismatch",
    select(2, store.extend("job-2/x", "WRONG", 100)))
  test("extend of a missing key", "no_such_key",
    select(2, store.extend("job-2/ghost", "L1", 100)))

  -- Repeated extension past 24h total is fine; each window is clamped.
  clockAt(90000)
  local ext2 = store.extend("job-2/x", "L1", 999999)
  test("re-extension clamps again", 90000 + 86400, ext2.expires_at)
end

-- ── 4. Release ──────────────────────────────────────────────────────
print()
print("-- release --")
do
  local FS = freshStore()
  clockAt(0)
  store.put("job-3/a", "payload")
  test("release needs a matching lease", "lease_mismatch",
    select(2, store.release("job-3/a", "NOPE")))
  test("...and the key survives", true, store.exists("job-3/a"))

  local rel = store.release("job-3/a", "L1")
  test("release succeeds",     true, rel ~= nil and rel.released)
  test("...key is gone",       false, store.exists("job-3/a"))
  test("...file is gone",      nil,  FS._files["/var/store/job-3/a"])
  test("...used is reclaimed", 0,    store.used())
  test("release of a missing key", "no_such_key",
    select(2, store.release("job-3/a", "L1")))
end

-- ── 5. Expiry and the sweep (§5) ────────────────────────────────────
print()
print("-- sweep --")
do
  freshStore()
  clockAt(0)
  store.put("job-4/short", "a", { ttl = 10 })
  store.put("job-4/long",  "b", { ttl = 1000 })

  clockAt(5)
  test("nothing expired yet", 0, store.sweep())
  test("...both still present", true, store.exists("job-4/short"))

  clockAt(50)
  test("sweep reaps the expired one", 1, store.sweep())
  test("...expired key gone",   false, store.exists("job-4/short"))
  test("...live key survives",  true,  store.exists("job-4/long"))
  test("...used reflects it",   1,     store.used())

  -- §5 is explicit that a key past expiry but not yet swept may still
  -- read. Pinning it so nobody "fixes" it into a hard check.
  clockAt(2000)
  test("unswept expired key still reads", "b", (store.get("job-4/long")))
  -- ...but reading it must not renew it, or a busy reader keeps a key
  -- alive forever past its lease.
  test("...and the sweep still takes it", 1, store.sweep())
end

-- ── 6. Eviction (§5.1) ──────────────────────────────────────────────
print()
print("-- eviction --")
do
  freshStore(100)          -- a deliberately tiny disk
  clockAt(0)
  store.put("job-5/a", string.rep("a", 40), { ttl = 10 })
  store.put("job-5/b", string.rep("b", 40), { ttl = 1000 })
  test("disk is nearly full", 20, store.free())

  -- Tier 1 beats tier 3, and the two must be made to DISAGREE or the
  -- test proves nothing. So touch the short-lived key while it is still
  -- live: now `a` is the expired one but the MOST recently accessed,
  -- and `b` is live but the least recently accessed. Pure LRU would
  -- take `b`; the §5.1 order takes `a`.
  clockAt(5)
  store.get("job-5/a")
  clockAt(500)
  local ack, err = store.put("job-5/c", string.rep("c", 40))
  test("put succeeds by evicting the expired key", "table", type(ack))
  test("...the EXPIRED key went, not the LRU one", false, store.exists("job-5/a"))
  test("...the live-but-stale key was spared",     true,  store.exists("job-5/b"))
  test("...no error",               nil,   err)

  -- Tier 3: with nothing expired, LRU gives way — least-recently
  -- accessed first, and only because the disk is genuinely full.
  clockAt(600); store.get("job-5/b")          -- touch b, so c is older
  local ack2 = store.put("job-5/d", string.rep("d", 40))
  test("LRU eviction makes room",  "table", type(ack2))
  test("...the untouched key went", false, store.exists("job-5/c"))
  test("...the touched key stayed", true,  store.exists("job-5/b"))
end

do
  -- A write bigger than the whole disk cannot be satisfied at any price,
  -- and must say so rather than evicting everything and still failing.
  freshStore(100)
  clockAt(0)
  store.put("job-6/keep", "x")
  local ack, err = store.put("job-6/huge", string.rep("z", 500))
  test("oversized put refused",     nil, ack)
  test("...as out_of_space",  "out_of_space", err and err:match("^[a-z_]+"))
end

-- ── 7. list ─────────────────────────────────────────────────────────
print()
print("-- list --")
do
  freshStore()
  clockAt(0)
  store.put("job-7/tasks/a", "1")
  store.put("job-7/tasks/b", "2")
  store.put("job-7/results/c", "3")
  store.put("domain-2/scratch/d", "4")

  local all = store.list("")
  test("lists everything", 4, #all)
  test("...sorted by key", "domain-2/scratch/d", all[1].key)

  local jobKeys = store.list("job-7/")
  test("prefix filters", 3, #jobKeys)
  local tasks = store.list("job-7/tasks/")
  test("deeper prefix filters further", 2, #tasks)
  test("...carries size", 1, tasks[1].size)

  local capped, truncated = store.list("", 2)
  test("limit caps the result", 2, #capped)
  test("...and says it truncated", true, truncated)
end

-- ── 8. Index durability ─────────────────────────────────────────────
print()
print("-- index --")
do
  local FS = freshStore()
  clockAt(0)
  store.put("job-8/a", "hello")
  store.put("job-8/b", "world")
  test("index file was written", true, FS._files["/var/store/.index"] ~= nil)
  test("no index temp left",     nil,  FS._files["/var/store/.index.tmp"])

  -- Restart against the same disk: the node must come back knowing what
  -- it holds, or every key on it becomes unreachable garbage.
  store.init({ root = "/var/store", capacity = 100000, fs = FS,
    computer = package.loaded["computer"], serialize = ser })
  test("index survives a restart", true, store.exists("job-8/a"))
  test("...with the payload",      "hello", (store.get("job-8/a")))
  test("...and the usage figure",  10, store.used())

  -- Index says a key exists but the payload is gone: trust the disk and
  -- repair, rather than serving a phantom.
  FS._files["/var/store/job-8/b"] = nil
  local d, err = store.get("job-8/b")
  test("phantom key reports missing", nil, d)
  test("...as no_such_key",   "no_such_key", err)
  test("...and is dropped from the index", false, store.exists("job-8/b"))
  test("...usage corrected",  5, store.used())
end

do
  -- A corrupt index must not present the node as empty: the payloads are
  -- still there, and an empty index would let them be overwritten.
  local FS = ramFS(100000)
  FS._files["/var/store/.index"] = "this is not a valid index"
  local ok = store.init({ root = "/var/store", capacity = 100000, fs = FS,
    computer = package.loaded["computer"], serialize = ser })
  local lok, lerr = store.loadIndex()
  test("corrupt index is refused", false, lok)
  test("...with a coded reason", "decode_failed", lerr and lerr:match("^[a-z_]+"))
end

-- ── 9. Error codes conform ──────────────────────────────────────────
-- error-conventions.md §4: stable snake_case code, optional detail.
print()
print("-- error-code conformance --")
do
  freshStore()
  clockAt(0)
  store.put("job-9/a", "x")
  local function isCoded(e)
    if type(e) ~= "string" then return false end
    return e:match("^[a-z][a-z0-9_]*$") ~= nil or e:match("^[a-z][a-z0-9_]*: .") ~= nil
  end
  local function errOf(...) local _, e = ...; return e end
  local cases = {
    { "validateKey/empty",  errOf(store.validateKey("")) },
    { "validateKey/abs",    errOf(store.validateKey("/x/y")) },
    { "put/bad data",       errOf(store.put("job-9/b", 1)) },
    { "put/exists",         errOf(store.put("job-9/a", "y", { overwrite = false })) },
    { "get/missing",        errOf(store.get("job-9/ghost")) },
    { "extend/missing",     errOf(store.extend("job-9/ghost", "L1", 10)) },
    { "extend/bad lease",   errOf(store.extend("job-9/a", "X", 10)) },
    { "release/bad lease",  errOf(store.release("job-9/a", "X")) },
    { "release/missing",    errOf(store.release("job-9/ghost", "L1")) },
  }
  for _, c in ipairs(cases) do
    test(c[1] .. " -> coded", true, isCoded(c[2]))
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
