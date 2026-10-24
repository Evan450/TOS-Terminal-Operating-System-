-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: cluster.store — the Storage Node's on-disk key store   ║
-- ║                                                              ║
-- ║  cluster-storage is 0.1.0 and held off the Optional Utilities ║
-- ║  pack while storage-spec-draft.md's distributed-pool design   ║
-- ║  stays open (§10) -- but the single-node store this skeleton   ║
-- ║  ships is real, injectable code with no test file of its own   ║
-- ║  until now. Everything here is pure given its injected fs/     ║
-- ║  computer/serialize, so it runs off-box against an in-memory    ║
-- ║  filesystem and a controllable clock.                           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua cluster/storage-skeleton/test_store.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local ROOT = "cluster/storage-skeleton/"
-- TOS-Dev is a sibling in the monorepo; the published dev branch nests us inside it.
local serialize = assert(loadfile("../TOS-Dev/tos/kernel/serialize.lua")
                         or loadfile("../tos/kernel/serialize.lua"))()

-- In-memory filesystem: the same shape kernel.fs offers, pared to what
-- store.lua actually calls.
local function fsStub()
  local files, dirs = {}, {}
  local fs = {
    makeDirectory = function(p) dirs[p] = true; return true end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, d) files[p] = d; return true end,
    remove = function(p) files[p] = nil; return true end,
    rename = function(a, b)
      if files[a] == nil then return false, "no such file" end
      files[b] = files[a]; files[a] = nil; return true
    end,
  }
  return fs, files, dirs
end

-- A controllable clock, since §5's TTL/lease math is the whole point of
-- several of these tests and a real wall clock would make them flaky
-- or slow.
local function clockOf()
  local t = 0
  return { uptime = function() return t end }, function(d) t = t + d end
end

local function freshStore(opts)
  local chunk = assert(loadfile(ROOT .. "usr/lib/cluster/store.lua"))
  local store = chunk()
  local fs, files, dirs = fsStub()
  local computer, advance = clockOf()
  store.init({
    fs = fs, computer = computer, serialize = serialize,
    root = "/var/cluster-store", capacity = (opts and opts.capacity) or 1000,
  })
  return store, files, dirs, advance
end

print("=== cluster.store Tests ===")
print()

-- ── Key validation (path-safety, independent of the namespace ACL) ──
do
  local store = freshStore()
  eq("a well-formed key validates", nil, (function()
    local segs, err = store.validateKey("job-1/tasks/a")
    return err
  end)())
  test("an absolute key is refused", select(2, store.validateKey("/job-1/x")) ~= nil)
  test("a trailing separator is refused", select(2, store.validateKey("job-1/x/")) ~= nil)
  test("an empty segment is refused", select(2, store.validateKey("job-1//x")) ~= nil)
  test("a '..' segment is refused", select(2, store.validateKey("job-1/../x")) ~= nil)
  test("a '.' segment is refused", select(2, store.validateKey("job-1/./x")) ~= nil)
  test("a bad character is refused", select(2, store.validateKey("job-1/x$y")) ~= nil)
  test("a single-segment key (no namespace) is refused", select(2, store.validateKey("onlyone")) ~= nil)
  test("an empty key is refused", select(2, store.validateKey("")) ~= nil)
  test("a non-string key is refused", select(2, store.validateKey(nil)) ~= nil)
  test("too many segments is refused",
    select(2, store.validateKey("a/b/c/d/e/f/g/h/i")) ~= nil)
  test("a key over MAX_KEY is refused",
    select(2, store.validateKey("job-1/" .. string.rep("x", 300))) ~= nil)
end

-- ── put/get round-trip ───────────────────────────────────────────────
do
  local store = freshStore()
  local ack, err = store.put("job-1/result", "hello world")
  test("put succeeds", ack ~= nil and err == nil)
  eq("put reports the key back", "job-1/result", ack and ack.key)
  eq("put reports the size", 11, ack and ack.size_bytes)
  test("put issues a lease id", ack and ack.lease_id ~= nil)

  local data, gerr = store.get("job-1/result")
  eq("get returns exactly what was put", "hello world", data)
  test("no error on a successful get", gerr == nil)
  test("exists() agrees", store.exists("job-1/result"))

  local missing, merr = store.get("job-1/nope")
  test("get on a missing key fails", missing == nil)
  eq("...with no_such_key", "no_such_key", merr)
end

-- ── overwrite=false refuses an existing key ─────────────────────────
do
  local store = freshStore()
  store.put("job-1/x", "first")
  local ack, err = store.put("job-1/x", "second", { overwrite = false })
  test("a conflicting put with overwrite=false is refused", ack == nil)
  eq("...the original value survives", "first", store.get("job-1/x"))
end

-- ── put accepts invalid data ─────────────────────────────────────────
do
  local store = freshStore()
  local ack, err = store.put("job-1/x", 12345)
  test("non-string data is refused", ack == nil)
  test("...with a reason", err ~= nil)
end

-- ── TTL / expiry: §5's own documented, non-obvious rule ─────────────
-- "a key past expiry but not yet swept MAY still return data" -- get()
-- does NOT refuse an expired key; only sweep()/evict() actually remove
-- it. This is the module's own stated contract, not a gap, and the
-- easiest thing in the file to accidentally "fix" into a regression.
do
  local store, _, _, advance = freshStore()
  store.put("job-1/x", "data", { ttl = 10 })
  advance(20)   -- past its expiry, never swept
  local data, err = store.get("job-1/x")
  eq("an expired-but-unswept key still reads", "data", data)
  test("exists() also still says yes (index-level, not a read)", store.exists("job-1/x"))
end

-- ── sweep() actually removes expired keys ───────────────────────────
do
  local store, files, _, advance = freshStore()
  store.put("job-1/stays", "a", { ttl = 100 })
  store.put("job-1/goes", "b", { ttl = 10 })
  advance(20)
  local n = store.sweep()
  eq("sweep reports exactly one removed", 1, n)
  test("the expired key is gone", not store.exists("job-1/goes"))
  test("the live key survives", store.exists("job-1/stays"))
  eq("get on the swept key now fails cleanly", "no_such_key",
    select(2, store.get("job-1/goes")))
end

-- ── Lease extend / release ───────────────────────────────────────────
do
  local store = freshStore()
  local ack = store.put("job-1/x", "data")
  local res, err = store.extend("job-1/x", ack.lease_id, 500)
  test("extend with the right lease succeeds", res ~= nil)
  test("a wrong lease id is refused",
    select(2, store.extend("job-1/x", "not-the-real-lease", 500)) == "lease_mismatch")
  test("extending a missing key fails", select(1, store.extend("job-1/nope", "x", 1)) == nil)

  local rel, rerr = store.release("job-1/x", ack.lease_id)
  test("release with the right lease succeeds", rel ~= nil)
  test("the key is actually gone after release", not store.exists("job-1/x"))

  store.put("job-1/y", "data")
  local ackY = store._internal.index()["job-1/y"]
  test("releasing with the wrong lease id is refused",
    select(2, store.release("job-1/y", "bogus")) == "lease_mismatch")
  test("...and the key survives a refused release", store.exists("job-1/y"))
end

-- ── Eviction (§5.1): tier 1 (expired) before tier 3 (LRU) ──────────
do
  local store, _, _, advance = freshStore({ capacity = 1000 })
  store.put("job-1/old-expired", string.rep("x", 100), { ttl = 5 })
  store.put("job-1/lru-a", string.rep("x", 100))
  advance(1)
  store.put("job-1/lru-b", string.rep("x", 100))
  advance(10)   -- the first key is now expired; the other two are not

  -- Ask for more than the expired key alone can free, so eviction must
  -- fall through to tier 3 (LRU) as well.
  local reclaimed = store.evict(150)
  test("eviction reclaims at least what was asked", reclaimed >= 150)
  test("the expired key goes first", not store.exists("job-1/old-expired"))
  test("the older LRU survivor (lru-a) is the one eviction took next",
    not store.exists("job-1/lru-a"))
  test("the most recently touched key survives", store.exists("job-1/lru-b"))
end

-- ── out_of_space, and self-healing via eviction ─────────────────────
-- §5.1: eviction may reclaim LIVE (non-expired) data under real
-- pressure, not only expired keys -- "a live lease is only broken when
-- the disk is genuinely full" is permission, not a promise it never
-- happens. So a put that doesn't fit ALONGSIDE existing data can still
-- succeed by evicting that data; only a put bigger than the entire
-- capacity -- which no amount of eviction can satisfy -- is refused.
do
  local store = freshStore({ capacity = 100 })
  local ack1 = store.put("job-1/a", string.rep("x", 60))
  test("a put that fits succeeds", ack1 ~= nil)

  local ack2, err2 = store.put("job-1/b", string.rep("x", 150))
  eq("a put bigger than total capacity is refused even after eviction", nil, ack2)
  test("...naming out_of_space", err2 and err2:find("out_of_space", 1, true) ~= nil)
  test("the failed attempt still evicted the smaller live key to try",
    not store.exists("job-1/a"))

  local ack3 = store.put("job-1/c", string.rep("x", 60))
  test("a put that fits (the store is empty again) succeeds", ack3 ~= nil)
  local ack4 = store.put("job-1/d", string.rep("x", 60))
  test("a second put that only fits by evicting the first LIVE key still succeeds",
    ack4 ~= nil)
  test("...and that first key is the one eviction took", not store.exists("job-1/c"))
end

-- ── list(): prefix match + limit truncation ─────────────────────────
do
  local store = freshStore()
  store.put("job-1/a", "1")
  store.put("job-1/b", "2")
  store.put("job-2/a", "3")
  local all, trunc1 = store.list("job-1/")
  eq("prefix match finds only matching keys", 2, #all)
  test("not truncated when under the limit", not trunc1)
  local limited, trunc2 = store.list("job-1/", 1)
  eq("limit caps the result", 1, #limited)
  test("truncated flag is set when the limit bit", trunc2)
  local none = store.list("job-3/")
  eq("a prefix matching nothing returns empty, not nil", 0, #none)
end

-- ── stats() / capacity / used / free bookkeeping ────────────────────
do
  local store = freshStore({ capacity = 500 })
  store.put("job-1/a", string.rep("x", 100))
  local s = store.stats()
  eq("stats counts the one key", 1, s.keys)
  eq("stats reports bytes used", 100, s.used_bytes)
  eq("stats reports capacity", 500, s.capacity_bytes)
  eq("free = capacity - used", 400, s.free_bytes)
  eq("used()/free() agree with stats()", s.used_bytes, store.used())
  eq("...free() too", s.free_bytes, store.free())

  -- Overwriting with a SMALLER value must shrink `used`, not just grow it.
  store.put("job-1/a", "x")
  eq("used shrinks when an overwrite is smaller", 1, store.used())
end

-- ── Index persistence: save/load round-trip, cold start, corruption ─
do
  local store, files = freshStore()
  store.put("job-1/a", "data")
  local ok = store.loadIndex()
  test("reloading the saved index succeeds", ok)
  eq("the key survives a reload", "data", store.get("job-1/a"))
end
do
  -- Cold start: no index file on disk at all yet.
  local store = freshStore()
  local ok, why = store.loadIndex()
  test("a cold start (no index file) is not an error", ok)
  eq("...and says so", "cold_start", why)
end
do
  -- A corrupt index must not be treated as "empty" -- that would look
  -- like silent data loss followed by overwriting what's still on disk.
  local store, files = freshStore()
  store.put("job-1/a", "data")
  files[store.indexPath()] = "{{{ not valid serialized data"
  local ok, why = store.loadIndex()
  test("a corrupt index refuses to load rather than pretending to be empty", not ok)
  eq("...and says why", "decode_failed: index", why)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
