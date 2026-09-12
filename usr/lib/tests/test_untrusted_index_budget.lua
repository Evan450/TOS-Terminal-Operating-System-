-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: an index or manifest from somewhere else      ║
-- ║  cannot make the decoder build more than a bounded heap         ║
-- ║                                                                ║
-- ║  pkgremote.index decodes a programs.cfg fetched from a repo     ║
-- ║  URL; pkg reads package.lua / programs.cfg off floppies and     ║
-- ║  network mounts before any signature is checked. Both had only  ║
-- ║  a byte cap, and a 128 KB index of "{{{}},...}" built 1.5 MB of ║
-- ║  tables (Sep 2026 pentest). Drives the REAL pkgremote.index and ║
-- ║  pkg's manifest reader (pkg._loadAnyManifest).                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_untrusted_index_budget.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }
package.loaded["kernel.sandbox"] = { build = function() return {} end }
package.loaded["kernel.users"] = { currentSession = function() return nil end }

local BODY
package.loaded["kernel.internet"] = {
  get = function() return BODY end,
  parseUrl = function() return true end,
}
local pkgremote = require("kernel.pkgremote")

-- Everything the call allocates, garbage included: the collector is off.
local function allocKB(fn)
  collectgarbage(); collectgarbage()
  local before = collectgarbage("count")
  collectgarbage("stop")
  local r1, r2 = fn()
  local used = collectgarbage("count") - before
  collectgarbage("restart")
  return used, r1, r2
end
local function nested(n) return "{" .. string.rep("{{}},", math.floor((n - 2) / 5)) .. "}" end
local function readReal(rel)
  for _, p in ipairs({ "../" .. rel, rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("a"); f:close(); return s end
  end
end
local LIMIT_KB = 80   -- the budget is 64 KB in Lua 5.3's sizes

print("=== a repo index is bounded ===")
print()
BODY = nested(128 * 1024)
local kb, idx = allocKB(function()
  return pkgremote.index({ name = "evil", url = "https://evil.example" }, { refresh = true })
end)
test(string.format("a hostile 128 KB index is refused after %.0f KB", kb), idx == nil and kb < LIMIT_KB)
BODY = nil

local realIndex = readReal("TOS-Extras/dist/optional-utilities/programs.cfg")
if realIndex then
  BODY = realIndex
  local idx2 = pkgremote.index({ name = "optutil", url = "https://tos.example" }, { refresh = true })
  local n = 0
  if type(idx2) == "table" then for _ in pairs(idx2) do n = n + 1 end end
  test(string.format("the real Optional Utilities index (%d B) still decodes: %d packages", #realIndex, n), n > 10)
  BODY = nil
else
  print("  SKIP: TOS-Extras is not beside TOS-Dev")
end

print()
print("-- a manifest off a floppy or a network mount is bounded --")
local pkg
for _, p in ipairs({ "tos/kernel/pkg.lua", "TOS-Dev/tos/kernel/pkg.lua" }) do
  local chunk = loadfile(p); if chunk then pkg = chunk(); break end
end
assert(pkg, "could not load pkg.lua")

local files, reads = {}, {}
local dirs = { ["/mnt"] = true, ["/mnt/evil"] = true, ["/mnt/evil/pa"] = true,
  ["/mnt/evil/pb"] = true, ["/mnt/good"] = true, ["/mnt/good/cluster-master"] = true }
local function norm(p)
  p = tostring(p):gsub("/+", "/")
  if #p > 1 then p = p:gsub("/$", "") end
  return p
end
local fsMock = {
  exists = function(p) p = norm(p); return files[p] ~= nil or dirs[p] == true end,
  isDirectory = function(p) return dirs[norm(p)] == true end,
  list = function() return {} end,
  join = function(...) return norm(table.concat({ ... }, "/")) end,
  normalize = norm,
  readFile = function(p) p = norm(p); reads[p] = true; return files[p] end,
  size = function(p) local f = files[norm(p)]; return f and #f or 0 end,
  makeDirectory = function() return true end,
  writeFile = function() return true end,
}
pkg.init({ fs = fsMock, log = nil, users = package.loaded["kernel.users"] })

files["/mnt/evil/pa/package.lua"] = nested(60 * 1024)    -- under the size cap: the budget refuses it
files["/mnt/evil/pb/package.lua"] = nested(300 * 1024)   -- over the size cap: never read
local kbA, mA = allocKB(function() return pkg._loadAnyManifest("/mnt/evil/pa") end)
test(string.format("a hostile 60 KB package.lua is refused after %.0f KB", kbA), mA == nil and kbA < LIMIT_KB)
local _, mB = allocKB(function() return pkg._loadAnyManifest("/mnt/evil/pb") end)
test("a 300 KB package.lua is refused without being read",
  mB == nil and not reads["/mnt/evil/pb/package.lua"])
files["/mnt/evil/pa/package.lua"], files["/mnt/evil/pb/package.lua"] = nil, nil

local good = readReal("TOS-Extras/dist/optional-utilities/disk1/cluster-master/package.lua")
if good then
  files["/mnt/good/cluster-master/package.lua"] = good
  local mG = pkg._loadAnyManifest("/mnt/good/cluster-master")
  test("a real package.lua (cluster-master, " .. #good .. " B) still loads",
    type(mG) == "table" and type(mG.name) == "string")
else
  print("  SKIP: TOS-Extras is not beside TOS-Dev")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
