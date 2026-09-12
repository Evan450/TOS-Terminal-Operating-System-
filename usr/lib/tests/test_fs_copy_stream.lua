-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: copying a file holds one block, not the file  ║
-- ║                                                                ║
-- ║  fs.copy read the whole source into one string and wrote it     ║
-- ║  back, so a copy needed the file's size in heap more than once: ║
-- ║  a 150 KB file could not be copied on a 256 KB machine (Sep     ║
-- ║  2026 pentest, RAM pass). fs.copyFile streams 4 KB blocks.      ║
-- ║                                                                ║
-- ║  The disk below samples LIVE heap at every read and discards    ║
-- ║  what is written (keeping a checksum), so the number measured   ║
-- ║  is the copy's own footprint. Drives the REAL kernel.fs.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_fs_copy_stream.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { yieldCooperative = function() end }
local fs = require("kernel.fs")

local SIZE = 200 * 1024
local SRC = string.rep("0123456789abcdef", SIZE // 16)
local function sum(s, acc) acc = acc or 0; for i = 1, #s, 97 do acc = (acc * 31 + s:byte(i)) % 2147483647 end; return acc end
local srcSum = sum(SRC)

local peak, base = 0, 0
local dirs = { ["/"] = true, ["/d"] = true }
local written = {}          -- path -> { len, sum }
local handles, nextH = {}, 1
local disk = { address = "d0" }
function disk.exists(p) return p == "/big.bin" or dirs[p] or written[p] ~= nil end
function disk.isDirectory(p) return dirs[p] == true end
function disk.makeDirectory(p) dirs[p] = true; return true end
function disk.list() return {} end
function disk.open(p, mode)
  local h = nextH; nextH = nextH + 1
  if mode == "r" then
    if p ~= "/big.bin" then return nil, "no such file" end
    handles[h] = { r = true, pos = 1 }
  else
    written[p] = { len = 0, sum = 0 }
    handles[h] = { w = p }
  end
  return h
end
function disk.read(h, n)
  collectgarbage(); collectgarbage()
  local live = collectgarbage("count") - base
  if live > peak then peak = live end
  local st = handles[h]
  if st.pos > #SRC then return nil end
  local chunk = SRC:sub(st.pos, st.pos + n - 1)
  st.pos = st.pos + #chunk
  return chunk
end
function disk.write(h, data)
  local w = written[handles[h].w]
  -- the checksum is order-sensitive over the whole stream, like the source's
  local off = w.len
  for i = 1, #data do
    if (off + i - 1) % 97 == 0 then w.sum = (w.sum * 31 + data:byte(i)) % 2147483647 end
  end
  w.len = w.len + #data
  return true
end
function disk.close(h) handles[h] = nil; return true end
function disk.remove() return true end
function disk.size(p) return p == "/big.bin" and SIZE or 0 end
disk.lastModified, disk.spaceTotal, disk.spaceUsed = function() return 0 end, function() return 1e8 end, function() return 0 end

fs.init(disk)

print("=== copying a file streams it ===")
print()
collectgarbage(); collectgarbage()
base = collectgarbage("count")
local ok, err = fs.copy("/big.bin", "/d/copy.bin")
test("a 200 KB file copies (" .. tostring(err) .. ")", ok == true)
test("every byte arrived, in order",
  written["/d/copy.bin"] and written["/d/copy.bin"].len == SIZE and written["/d/copy.bin"].sum == srcSum)
test(string.format("the copy held at most a couple of blocks live (peak %.1f KB)", peak), peak < 32)
test("copying a path onto itself leaves it alone", fs.copy("/big.bin", "/big.bin") == true)
test("a missing source is an error, not a crash", fs.copy("/nope", "/d/x") == false)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
