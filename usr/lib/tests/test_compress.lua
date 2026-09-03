-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Disk Compression (kernel.compress)  ║
-- ║  - pack/unpack round-trip: stored + compressed paths   ║
-- ║  - detection gating (no card => store-only, no crash)  ║
-- ║  - multi-chunk framing                                 ║
-- ║  - compressed blob needs a card to inflate             ║
-- ║  - swap transparently compresses + restores            ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compress.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_compress.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadChunk(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- A fake data card whose deflate returns a short token and inflate reverses
-- it via a shared dictionary. This is reversible and genuinely "shrinks", so
-- both the framing AND the worth-it branch get exercised without real zlib.
local function newFakeCard()
  local dict, n = {}, 0
  return {
    deflate = function(s)
      n = n + 1; local tok = "R" .. n; dict[tok] = s; return tok
    end,
    inflate = function(tok) return dict[tok] end,
  }
end

local function newComponent(card)
  return {
    list = function()
      local done = false
      return function()
        if done or not card then return nil end
        done = true; return "data-addr"
      end
    end,
    proxy = function() return card end,
  }
end

-- Fresh compress module bound to a chosen component stub.
local function freshCompress(card)
  package.loaded["component"] = newComponent(card)
  package.loaded["kernel.compress"] = nil
  local chunk = loadChunk("compress.lua")
  if not chunk then return nil end
  local cz = chunk()
  cz.init({})
  return cz
end

print("=== Disk Compression Tests ===")
print()

-- ── With a data card ────────────────────────────────────────────────
local card = newFakeCard()
local cz = freshCompress(card)
if not cz then
  print("FAIL: could not load compress.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
test("available with card", true, cz.available())

-- Tiny payload -> stored (below MIN_COMPRESS), still round-trips.
local tiny = "hello"
local tblob, tmethod = cz.pack(tiny)
test("tiny payload stored (not compressed)", "stored", tmethod)
test("isPacked recognizes blob", true, cz.isPacked(tblob))
test("tiny round-trip", tiny, cz.unpack(tblob))

-- Large, multi-chunk payload -> compressed, smaller, round-trips exactly.
local big = string.rep("abcdefghij0123456789", 1000)  -- 20000 bytes, >4 chunks
local bblob, bmethod, orig, packed = cz.pack(big)
test("large payload compressed", "deflate", bmethod)
test("compressed reports original size", 20000, orig)
test("compressed is smaller than original", true, packed < orig)
test("large round-trip exact", big, cz.unpack(bblob))

-- isPacked false on arbitrary bytes.
test("isPacked false on plain data", false, cz.isPacked("just some text"))

-- ── Without a data card ─────────────────────────────────────────────
local sw = freshCompress(nil)
test("unavailable without card", false, sw.available())
local sblob, smethod = sw.pack(big)
test("no card -> stored frame", "stored", smethod)
test("no card stored round-trips (no card needed)", big, sw.unpack(sblob))
-- A blob compressed WITH a card cannot inflate WITHOUT one.
local noData, err = sw.unpack(bblob)
test("compressed blob needs a card to inflate", nil, noData)
test("…with a clear error", true, type(err) == "string" and err:find("data card") ~= nil)

-- ── Corrupt / truncated containers answer, they don't raise ────
-- unpack's contract is (data) or (nil, err) — `decompress` calls it
-- unprotected and prints the err. isPacked accepts anything from 9 bytes
-- up (a STORED container's header), but a COMPRESSED one needs 11 before
-- the chunk count can be read, so a container truncated to 9 or 10 used to
-- reach the u16 read with nothing there and raise 'bitwise operation on a
-- nil value'. The operator got a Lua traceback where an error message
-- belonged. Longer truncations were always caught inside the chunk loop;
-- it was only the header that went unchecked.
do
  local F_COMPRESSED = 1
  local hdr = cz.MAGIC .. string.char(F_COMPRESSED) .. string.char(0, 0, 0, 5)
  local function attempt(blob)
    local ok, a, b = pcall(cz.unpack, blob)
    if not ok then return "RAISED: " .. tostring(a) end
    return a, b
  end

  test("a 9-byte compressed container is still recognised", true, cz.isPacked(hdr))
  local r9, e9 = attempt(hdr)
  test("...and unpack RETURNS rather than raising", nil, r9)
  test("...with a truncation error", true,
    type(e9) == "string" and e9:find("truncat") ~= nil)

  local r10, e10 = attempt(hdr .. string.char(0))
  test("a 10-byte one likewise returns", nil, r10)
  test("...with a truncation error", true,
    type(e10) == "string" and e10:find("truncat") ~= nil)

  -- 11 bytes is a complete header claiming one chunk whose length is
  -- missing: the chunk loop already handled this, and must keep doing so.
  local r11, e11 = attempt(hdr .. string.char(0, 1))
  test("a header with no chunk data returns too", nil, r11)
  test("...with a truncation error", true,
    type(e11) == "string" and e11:find("truncat") ~= nil)

  -- A STORED container of exactly 9 bytes is legal: empty payload.
  local empty = cz.MAGIC .. string.char(0) .. string.char(0, 0, 0, 0)
  test("an empty STORED container still decodes to \"\"", "", (attempt(empty)))
end
-- ── Swap integration: transparent compress on store/fetch ───────────
local serialize = (function()
  local c = loadChunk("serialize.lua"); return c and c()
end)()
package.loaded["kernel.serialize"] = serialize
local swap = (function()
  package.loaded["kernel.swap"] = nil
  local c = loadChunk("swap.lua"); return c and c()
end)()

local function newFS()
  local files, dirs = {}, { ["/"] = true, ["/var"] = true }
  local function parent(p) return p:match("^(.+)/[^/]+$") end
  return {
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    spaceFree = function() return 1 << 24 end,
    list = function(p)
      local out = {}
      for path in pairs(files) do
        if parent(path) == p then out[#out + 1] = path:match("[^/]+$") end
      end
      return out
    end,
    writeFile = function(p, data) local d = parent(p); if d then dirs[d] = true end; files[p] = data; return true end,
    readFile = function(p) return files[p] end,
    remove = function(p)
      if files[p] ~= nil then files[p] = nil; return true end
      if dirs[p] then dirs[p] = nil; return true end
      return false
    end,
    _files = files,
  }
end

if serialize and swap then
  local fs = newFS()
  -- Use a fresh card-backed compress instance for swap.
  local swCz = freshCompress(newFakeCard())
  swap.init({ fs = fs, serialize = serialize, config = nil, compress = swCz })

  local payload = { tag = "log", lines = {} }
  for i = 1, 500 do payload.lines[i] = "repeated line of cold data " .. (i % 7) end
  local rawLen = #serialize.encode(payload)

  test("swap.store with compression ok", true, (swap.store("k1", payload)))
  local got = swap.fetch("k1")
  test("swap.fetch round-trips compressed value", "log", got and got.tag)
  test("swap.fetch line count intact", 500, got and #got.lines)
  test("swap.fetch line content intact", "repeated line of cold data 3", got and got.lines[3])
  -- The on-disk usage should be below the raw serialized size (compression won).
  local u = swap.usage()
  test("swap usage reflects compressed (smaller) bytes", true, u.bytes < rawLen)
else
  test("swap/serialize loaded for integration", true, false)
end

print()
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed == 0 then print("*** ALL TESTS PASSED ***"); return true
else print("*** TESTS FAILED ***"); return false end
