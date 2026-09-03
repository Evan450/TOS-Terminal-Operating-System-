-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Disk Swap (spill-to-disk slow RAM)  ║
-- ║  - store/fetch/free round-trip + usage accounting      ║
-- ║  - size-cap enforcement (no silent overrun)            ║
-- ║  - table proxy: get/set/delete, LRU spill, pairs, free ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_swap.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_swap.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

-- Real serialize so round-trips are genuine (tables, numbers, strings).
local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
local swap = loadMod("swap.lua")
if not serialize or not swap then
  print("FAIL: could not load swap.lua / serialize.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- ── Minimal in-memory fs (high-level kernel.fs API surface swap uses) ──
local function newFS()
  local files, dirs = {}, { ["/"] = true, ["/var"] = true }
  local function parent(p) return p:match("^(.+)/[^/]+$") end
  return {
    exists      = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    spaceFree   = function() return 1 << 24 end,  -- 16 MB, plenty
    list = function(p)
      local out = {}
      for path in pairs(files) do
        if parent(path) == p then out[#out + 1] = path:match("[^/]+$") end
      end
      return out
    end,
    writeFile = function(p, data)
      local d = parent(p); if d then dirs[d] = true end
      files[p] = data; return true
    end,
    readFile = function(p) return files[p] end,
    remove   = function(p)
      if files[p] ~= nil then files[p] = nil; return true end
      if dirs[p] then dirs[p] = nil; return true end
      return false
    end,
    _files = files,
  }
end

print("=== Disk Swap Tests ===")
print()

-- ── Store API round-trip ───────────────────────────────────────────
local fs = newFS()
swap.init({ fs = fs, serialize = serialize, config = nil })

test("store string", true, (swap.store("greeting", "hello")))
test("fetch string", "hello", swap.fetch("greeting"))
test("store + fetch number", 42, (function() swap.store("n", 42); return swap.fetch("n") end)())
local tbl = { a = 1, b = { 2, 3 }, c = "x" }
swap.store("cfg", tbl)
local got = swap.fetch("cfg")
test("fetch table (nested)", true, type(got) == "table" and got.a == 1 and got.b[2] == 3 and got.c == "x")
test("has present key", true, swap.has("greeting"))
test("has absent key", false, swap.has("nope"))
test("fetch absent -> nil", nil, swap.fetch("nope"))

local u = swap.usage()
test("usage counts entries", 3, u.count)  -- greeting, n, cfg
test("free removes", true, swap.free("n"))
test("freed key gone", false, swap.has("n"))
test("usage after free", 2, swap.usage().count)
-- store(key, nil) frees.
swap.store("greeting", nil)
test("store nil frees", false, swap.has("greeting"))

-- ── Cap enforcement ────────────────────────────────────────────────
local fs2 = newFS()
swap.init({ fs = fs2, serialize = serialize,
  config = { get = function(k) return k == "swapMaxKB" and 1 or nil end } })  -- 1 KB cap
local payload = string.rep("x", 400)  -- ~ >400 bytes encoded
local ok1 = swap.store("a", payload)
local ok2 = swap.store("b", payload)
local ok3, err3 = swap.store("c", payload)  -- should overflow 1 KB
test("first fits under cap", true, ok1)
test("third overflows cap", false, ok3)
test("overflow gives reason", true, type(err3) == "string" and err3:find("full") ~= nil)
-- Overwriting an existing key reclaims its bytes, so replacing 'a' with a
-- tiny value frees room for 'c'.
swap.store("a", "tiny")
test("room reclaimed lets c fit", true, (swap.store("c", payload)))

-- ── clear ───────────────────────────────────────────────────────────
swap.clear()
test("clear empties usage", 0, swap.usage().count)

-- ── Table proxy ─────────────────────────────────────────────────────
local fs3 = newFS()
swap.init({ fs = fs3, serialize = serialize, config = nil })
local t = swap.table({ hot = 2 })   -- tiny hot-cache to force LRU spill
t.name = "alice"
t[1] = "first"
t.data = { nested = true }
test("proxy get string", "alice", t.name)
test("proxy get int key", "first", t[1])
test("proxy get table", true, type(t.data) == "table" and t.data.nested == true)
test("proxy __len", 3, #t)

-- Force LRU eviction: with hot=2, touching several keys evicts older
-- cache entries, but they must still be readable from disk.
t.x1 = 1; t.x2 = 2; t.x3 = 3; t.x4 = 4
test("evicted key still readable from disk", "alice", t.name)
test("evicted int key still readable", "first", t[1])

-- pairs() iterates all keys.
local seen, count = {}, 0
for k, v in pairs(t) do seen[tostring(k)] = v; count = count + 1 end
test("pairs sees all keys", 7, count)  -- name,1,data,x1,x2,x3,x4
test("pairs yields correct value (string key)", "alice", seen["name"])
test("pairs yields correct value (int key)", "first", seen["1"])

-- delete via nil.
t.name = nil
test("proxy delete via nil", nil, t.name)
test("proxy __len after delete", 6, #t)

-- freeTable releases all entries.
local before = swap.usage().count
test("freeTable succeeds", true, (swap.freeTable(t)))
test("freeTable cleared entries", 0, swap.usage().count)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
