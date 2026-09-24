-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a refused write is a failed write               ║
-- ║                                                                    ║
-- ║  OC hands soft errors back as VALUES, not raises. OpenOS reports   ║
-- ║  a full disk as `write() -> nil, "not enough space"`               ║
-- ║  (lib/buffer.lua); some proxies answer `false, err`. pcall sees    ║
-- ║  neither, so `local ok = pcall(proxy.write, ...)` was true for     ║
-- ║  both and fs.writeFile returned success having written nothing --  ║
-- ║  after open(path,"w") had already truncated the file.              ║
-- ║                                                                    ║
-- ║  The damage is not the lost write, it is writeFileAtomic. Built    ║
-- ║  on writeFile, it believed the temp was good, REMOVED the real     ║
-- ║  file and renamed the empty temp over it -- so the guard whose     ║
-- ║  whole job is "either the intact old file or the intact new one"   ║
-- ║  delivered neither, and said ok. That path carries                 ║
-- ║  /etc/users.dat, the elevate DB and the trust DB.                  ║
-- ║                                                                    ║
-- ║  fs.copyFile had half of it: it tested `w == false` and missed     ║
-- ║  the nil shape, which is the one OpenOS actually produces.         ║
-- ║                                                                    ║
-- ║  The disk below is a real truncate-on-open filesystem whose        ║
-- ║  writes can be told to refuse in either shape. Drives the REAL     ║
-- ║  kernel.fs -- the point is what the kernel does with the answer.   ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_fs_write_full.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["computer"]  = { uptime = function() return 0 end, pullSignal = function() end }
package.loaded["kernel.process"] = { yieldCooperative = function() end }
local fs = require("kernel.fs")

-- ── A disk that truncates on open("w") and can refuse writes ──
-- refuse: nil (accept) | "nil" (return nil, err) | "false" (return false, err)
local store, dirs, handles, nextH = {}, { ["/"] = true }, {}, 1
local refuse = nil

local disk = { address = "d0" }
function disk.exists(p) return store[p] ~= nil or dirs[p] == true end
function disk.isDirectory(p) return dirs[p] == true end
function disk.makeDirectory(p) dirs[p] = true; return true end
function disk.list() return {} end
function disk.size(p) return store[p] and #store[p] or 0 end
function disk.lastModified() return 0 end
function disk.spaceTotal() return 4194304 end
function disk.spaceUsed() return refuse and 4194304 or 0 end
function disk.remove(p) store[p] = nil; return true end
function disk.rename(a, b) store[b] = store[a]; store[a] = nil; return true end
function disk.open(p, mode)
  local h = nextH; nextH = nextH + 1
  -- Truncate-on-open is the whole reason this bug destroys data.
  if mode == "w" then store[p] = "" end
  if mode == "r" and store[p] == nil then return nil, "no such file" end
  handles[h] = { path = p, mode = mode, pos = 1 }
  return h
end
function disk.write(h, data)
  if refuse == "nil"   then return nil,   "not enough space" end
  if refuse == "false" then return false, "not enough space" end
  local st = handles[h]; if not st then return nil, "bad handle" end
  store[st.path] = (store[st.path] or "") .. data
  return true
end
function disk.read(h, n)
  local st = handles[h]; if not st then return nil end
  local s = store[st.path] or ""
  if st.pos > #s then return nil end
  local chunk = s:sub(st.pos, st.pos + n - 1)
  st.pos = st.pos + #chunk
  return chunk
end
function disk.close(h) handles[h] = nil; return true end

fs.init(disk)

print("=== a refused write is a failed write ===")
print()

-- ── 1. writeFile reports the refusal, in both shapes ──
for _, shape in ipairs({ "nil", "false" }) do
  store["/data.txt"] = "old contents"
  refuse = shape
  local ok, err = fs.writeFile("/data.txt", "new contents")
  refuse = nil
  test("writeFile: write() -> " .. shape .. " is reported as failure", ok == false)
  test("writeFile: write() -> " .. shape .. " says why (" .. tostring(err) .. ")",
    type(err) == "string" and err:find("not enough space", 1, true) ~= nil)
end

-- ── 2. appendFile likewise ──
store["/log.txt"] = "line one\n"
refuse = "nil"
local aok = fs.appendFile("/log.txt", "line two\n")
refuse = nil
test("appendFile: a refused append is reported as failure", aok == false)

-- ── 3. THE ONE THAT COST DATA: writeFileAtomic must not eat the target ──
store["/etc/users.dat"] = "root:REAL-ACCOUNT-DATA"
refuse = "nil"
local wok, werr = fs.writeFileAtomic("/etc/users.dat", "root:NEW-DATA")
refuse = nil
test("writeFileAtomic: a refused write is reported as failure", wok == false)
test("writeFileAtomic: the ORIGINAL file is still intact (" ..
  string.format("%q", tostring(store["/etc/users.dat"])) .. ")",
  store["/etc/users.dat"] == "root:REAL-ACCOUNT-DATA")
test("writeFileAtomic: no temp is left behind",
  store["/etc/users.dat" .. ".tos-tmp"] == nil)
test("writeFileAtomic: the failure says why (" .. tostring(werr) .. ")",
  type(werr) == "string" and werr ~= "")

-- ── 4. copyFile catches BOTH shapes, not just `false` ──
refuse = nil
store["/src.bin"] = "important payload"
for _, shape in ipairs({ "false", "nil" }) do
  refuse = shape
  local cok = fs.copyFile("/src.bin", "/dst-" .. shape .. ".bin")
  refuse = nil
  test("copyFile: write() -> " .. shape .. " aborts the copy", cok == false)
end

-- ── 5. The happy path still works (the check must not cost a real write) ──
refuse = nil
test("writeFile still writes when the disk accepts",
  fs.writeFile("/ok.txt", "hello") == true and store["/ok.txt"] == "hello")
test("appendFile still appends",
  fs.appendFile("/ok.txt", " world") == true and store["/ok.txt"] == "hello world")
test("writeFileAtomic still replaces the target",
  fs.writeFileAtomic("/etc/users.dat", "root:ROTATED") == true
  and store["/etc/users.dat"] == "root:ROTATED")
test("copyFile still copies",
  fs.copyFile("/src.bin", "/copy.bin") == true
  and store["/copy.bin"] == "important payload")

-- ── 6. A proxy that returns NOTHING is still the historical success shape.
-- Several in-tree mocks (and older proxies) answer write() with no value at
-- all; treating a bare nil as refusal would break every one of them, so only
-- an explicit nil-PLUS-reason or false counts as a refusal.
local quiet = {}
for k, v in pairs(disk) do quiet[k] = v end
quiet.address = "d1"
quiet.write = function(h, data)
  local st = handles[h]; if not st then return end
  store[st.path] = (store[st.path] or "") .. data
  -- returns nothing
end
fs.mount("/quiet", quiet)
test("a proxy whose write() returns nothing is still treated as success",
  fs.writeFile("/quiet/q.txt", "silent") == true and store["/q.txt"] == "silent")

-- ── 7. A target that will not be removed ────────────────────────────
-- fs.remove reports a refusal as `false, err` and never raises, so the
-- old `pcall(fs.remove, path)` guard was always true: the refusal surfaced
-- later as "rename failed" (rename will not overwrite on a Windows host)
-- and the temp was left for the next boot to clean up.
local stubborn = {}
for k, v in pairs(disk) do stubborn[k] = v end
stubborn.address = "d2"
stubborn.remove = function(p)
  if p == "/pinned.dat" then return false end
  store[p] = nil; return true
end
stubborn.rename = function(a, b)
  if store[b] ~= nil then return false end   -- no overwrite, as on Windows
  store[b] = store[a]; store[a] = nil; return true
end
fs.mount("/stubborn", stubborn)
refuse = nil
store["/pinned.dat"] = "KEEP"
local sok, serr = fs.writeFileAtomic("/stubborn/pinned.dat", "NEW")
test("an unremovable target is reported as such (" .. tostring(serr) .. ")",
  sok == false and tostring(serr):find("cannot replace target", 1, true) ~= nil)
test("...the target is untouched", store["/pinned.dat"] == "KEEP")
test("...and no temp is left behind", store["/pinned.dat.tos-tmp"] == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
