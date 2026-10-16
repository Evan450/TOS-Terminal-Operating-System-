-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.pkg is two files, and nobody can tell  ║
-- ║                                                                ║
-- ║  Every package command, every `pkg list` and (on a machine with ║
-- ║  packages) every typo loaded the whole package manager, ~190 KB ║
-- ║  compiled, and kept it. The core now holds what a package       ║
-- ║  COMMAND needs; kernel.pkgops (install, upgrade, plan, repos,   ║
-- ║  trust, remote...) loads the first time anything asks pkg for   ║
-- ║  one of its names. This holds the seam:                         ║
-- ║    * the core's everyday calls never load the operations;       ║
-- ║    * pkg._OPS_NAMES is exactly what kernel.pkgops defines;      ║
-- ║    * they load once, and pkg.init re-attaches them on the new   ║
-- ║      fs; a caller's own stub survives both;                     ║
-- ║    * a load that fails is an ordinary failure, not a crash.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_split.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }
package.loaded["kernel.sandbox"] = { build = function() return {} end }
local ROOT = { tier = 3, user = "root" }
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 }, currentSession = function() return ROOT end }
package.loaded["kernel.sha256"] = dofile("tos/kernel/sha256.lua")
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = { hash = function(d) return sha.hex(d) end,
                                    ctEquals = function(a, b) return a == b end }

local function newFS()
  local F = { _f = {} }
  local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
  function F.exists(p) for k in pairs(F._f) do if under(p, k) then return true end end return false end
  function F.readFile(p) return F._f[p] end
  function F.writeFile(p, d) F._f[p] = d; return true end
  function F.writeFileAtomic(p, d) F._f[p] = d; return true end
  function F.remove(p) for k in pairs(F._f) do if under(p, k) then F._f[k] = nil end end return true end
  function F.isDirectory(p) return F.exists(p) and F._f[p] == nil end
  function F.makeDirectory() return true end
  function F.mounts() return {} end
  function F.list(p) local out, seen = {}, {} for k in pairs(F._f) do if k:sub(1, #p + 1) == p .. "/" then local h = k:sub(#p + 2):match("^([^/]+)") if h and not seen[h] then seen[h] = true out[#out + 1] = h end end end return out end
  function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
  function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
  return F
end
local F = newFS()
package.loaded["kernel.fs"] = F

-- Count loads and attaches of the operations, and let a test make it fail.
local realFactory = dofile("tos/kernel/pkgops.lua")
local loads, attaches, failWith = 0, 0, nil
package.preload["kernel.pkgops"] = function()
  loads = loads + 1
  if failWith then error(failWith, 0) end
  return function(p, C) attaches = attaches + 1; return realFactory(p, C) end
end

local function freshPkg(fs)
  package.loaded["kernel.pkgops"] = nil
  local pkg = dofile("tos/kernel/pkg.lua")
  pkg.init({ fs = fs, log = nil, users = package.loaded["kernel.users"] })
  return pkg
end

local function put(fs, dir, name, extra)
  local body = "return '" .. name .. "'\n"
  local m = { name = name, version = "1.0.0", kind = "command", description = name,
    files = { "/usr/lib/" .. name .. ".lua" }, hashes = { ["/usr/lib/" .. name .. ".lua"] = sha.hex(body) },
    capabilities = {}, commands = { [name] = "/usr/lib/" .. name .. ".lua" } }
  for k, v in pairs(extra or {}) do m[k] = v end
  fs._f[dir .. "/" .. name .. "/package.lua"] = serialize.encode(m)
  fs._f[dir .. "/" .. name .. "/usr/lib/" .. name .. ".lua"] = body
end

print("=== kernel.pkg is two files, and nobody can tell ===")
print()

-- ── The everyday calls are the core's ──────────────────────────────
local pkg = freshPkg(F)
test("loading and initialising pkg does not load the operations", loads == 0, loads)
local _ = pkg.list(); _ = pkg.info("x"); _ = pkg.isEnabled("x"); _ = pkg.commands()
_ = pkg.getCommand("nothing"); _ = pkg.capsForFile("/usr/bin/x.lua"); _ = pkg.ownerOfCommand("x")
_ = pkg.checkRequires("x"); _ = pkg.compareVersion("1.0", "2.0"); _ = pkg.criticalFiles()
pkg.scan(); pcall(pkg.syncCriticalBackup)
test("list, info, isEnabled, commands, getCommand, caps, versions, scan: still not", loads == 0, loads)

-- ── The name list is exactly what the operations define ────────────
do
  local defined = {}
  local rec = setmetatable({}, { __newindex = function(t, k, v) defined[k] = true; rawset(t, k, v) end })
  realFactory(rec, { fs = F, installed = {} })
  local missing, extra = {}, {}
  for k in pairs(defined) do if not pkg._OPS_NAMES[k] then missing[#missing + 1] = k end end
  for k in pairs(pkg._OPS_NAMES) do if not defined[k] then extra[#extra + 1] = k end end
  table.sort(missing); table.sort(extra)
  test("every name kernel.pkgops defines is in pkg._OPS_NAMES", #missing == 0, table.concat(missing, " "))
  test("...and nothing else is", #extra == 0, table.concat(extra, " "))
  local overlap = {}
  for k in pairs(defined) do if rawget(pkg, k) ~= nil then overlap[#overlap + 1] = k end end
  test("no name is defined by both halves", #overlap == 0, table.concat(overlap, " "))
end

-- ── They load once, on first use ───────────────────────────────────
put(F, "/mnt/disk1", "hello")
local ok, why = pkg.install("/mnt/disk1/hello", { session = ROOT })
test("the first operation loads them, and works", ok == true and loads == 1 and attaches == 1, why)
test("...and the core sees what it installed", pkg.info("hello") ~= nil and pkg.commands().hello ~= nil)
_ = pkg.findInRepos("hello", { "/mnt/disk1" }); _ = pkg.describeConflicts({})
test("later operations reuse them", loads == 1 and attaches == 1, attaches)
pkg.scan()
local okU = pkg.uninstall("hello", { session = ROOT })
test("after a rescan the operations still see the registry (scan clears it in place)",
  okU == true and pkg.info("hello") == nil)

-- ── pkg.init re-attaches them on the new fs ────────────────────────
local F2 = newFS()
put(F2, "/mnt/other", "second")
pkg.init({ fs = F2, log = nil, users = package.loaded["kernel.users"] })
test("init drops them...", rawget(pkg, "install") == nil)
ok, why = pkg.install("/mnt/other/second", { session = ROOT })
test("...and the next operation runs on the NEW fs", ok == true and F2._f["/usr/lib/second.lua"] ~= nil
  and F._f["/usr/lib/second.lua"] == nil and attaches == 2, why)

-- ── A caller's own stub survives ───────────────────────────────────
pkg = freshPkg(newFS())
loads, attaches = 0, 0
local stub = function() return { { name = "stubbed" } } end
pkg.listRepo = stub
_ = pkg.describeConflicts({})
test("a stub set before the operations load stays in place", pkg.listRepo == stub and attaches == 1)
local stub2 = function() return "mine" end
pkg.planByName = stub2
pkg.init({ fs = newFS(), log = nil, users = package.loaded["kernel.users"] })
test("...and one set after survives init's drop", pkg.planByName == stub2 and pkg.listRepo == stub)
test("...while the operations' own functions are dropped", rawget(pkg, "install") == nil)

-- ── A load that fails is an ordinary failure ───────────────────────
pkg = freshPkg(newFS())
failWith = "not enough memory"
local okF, whyF = pkg.install("/mnt/disk1/x", { session = ROOT })
test("if the operations cannot load, a call fails with the reason",
  okF == false and tostring(whyF):find("not enough memory", 1, true) ~= nil, whyF)
test("...a constant reads as nil, not as a function", pkg.DEFAULT_REPO_ROOTS == nil)
test("...and nothing is cached", rawget(pkg, "install") == nil)
failWith = nil
package.loaded["kernel.pkgops"] = nil
test("once they can load, the next call does", type(pkg.install) == "function"
  and type(pkg.DEFAULT_REPO_ROOTS) == "table")

-- ── It ships ───────────────────────────────────────────────────────
do
  local f = io.open("tos/system_manifest.lua", "rb")
  local man = f and f:read("*a") or ""
  if f then f:close() end
  test("the system manifest lists kernel.pkgops", man:find('"/tos/kernel/pkgops.lua"', 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
