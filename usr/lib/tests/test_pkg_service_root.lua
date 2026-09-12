-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: installing a SERVICE package needs ROOT       ║
-- ║                                                                ║
-- ║  A service package is trusted with the machine: rc.d runs it    ║
-- ║  as the principal it declares, and as ROOT when it declares     ║
-- ║  none, through the kernel loader -- outside the capability      ║
-- ║  sandbox a command package runs in (MANUAL §15). pkg.install    ║
-- ║  required only ADMIN, so any admin could run code as root at    ║
-- ║  the next boot, and every ROOT-only line elsewhere was a        ║
-- ║  courtesy an admin could walk around (Sep 2026 pentest). A      ║
-- ║  service install now needs ROOT; command/app/lib/driver stay    ║
-- ║  ADMIN. Drives the REAL pkg.install / pkg.upgrade / installWith-║
-- ║  Deps over an in-memory disk (as test_pkg_lifecycle does).      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_service_root.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_service_root.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p); if chunk then return chunk() end
  end
end

local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha256 = loadMod("sha256.lua")
package.loaded["kernel.sha256"] = sha256
package.loaded["kernel.crypto"] = {
  hash = function(s) return sha256.hex(s) end,
  ctEquals = function(a, b) return a == b end,
}

local function newFS()
  local files, dirs = {}, { ["/"] = true }
  local F
  F = {
    _files = files,
    normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
    join = function(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, c)
      local acc = ""
      for seg in tostring(p):gmatch("[^/]+") do
        acc = acc .. "/" .. seg
        if acc ~= p then dirs[acc] = true end
      end
      files[p] = c; return true
    end,
    writeFileAtomic = function(p, c) return F.writeFile(p, c) end,
    remove = function(p) files[p] = nil; return true end,
    list = function(p)
      local out, seen = {}, {}
      p = tostring(p):gsub("/$", "")
      local pat = "^" .. p:gsub("%p", "%%%1") .. "/([^/]+)"
      for k in pairs(files) do
        local rest = k:match(pat)
        if rest and not seen[rest] then seen[rest] = true; out[#out + 1] = rest end
      end
      for k in pairs(dirs) do
        local rest = k:match(pat .. "$")
        if rest and not seen[rest] then seen[rest] = true; out[#out + 1] = rest .. "/" end
      end
      table.sort(out); return out
    end,
    size = function(p) return files[p] and #files[p] or 0 end,
  }
  return F
end

local TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 }
local ADMIN = { user = "alice", tier = TIER.ADMIN }
local ROOT  = { user = "root",  tier = TIER.ROOT }
local usersMock = {
  currentSession = function() return nil end,   -- callers pass opts.session
  TIER = TIER,
  canAccessAs = function() return true end,
  getUser = function(n) return n == "root" and { name = "root", tier = TIER.ROOT }
    or { name = n, tier = TIER.USER } end,
}
local function newPkg()
  local fs = newFS()
  package.loaded["kernel.pkg"] = nil
  local pkg = loadMod("pkg.lua")
  pkg.init({ fs = fs, log = nil, users = usersMock })
  return pkg, fs
end
-- Lay a package repo dir down, with hashes so the verification gate passes.
local function putPkg(fs, name, m, bodies)
  local dir = "/usr/repo/" .. name
  fs.makeDirectory(dir)
  m.hashes = {}
  for target, body in pairs(bodies) do
    m.hashes[target] = sha256.hex(body)
    fs.writeFile(dir .. target, body)
  end
  fs.writeFile(dir .. "/package.lua", serialize.encode(m))
  return dir
end

-- A service package: an rc.d entry (a stem NOT on the kernel-tier allowlist)
-- plus a lib. This is exactly the shape rc.d runs as root.
local function serviceManifest(name)
  return { name = name, version = "1.0.0", kind = "service",
    files = { "/usr/lib/" .. name .. ".lua", "/etc/rc.d/40-" .. name .. ".lua" } }
end
local function serviceBodies(name)
  return { ["/usr/lib/" .. name .. ".lua"] = "return {}",
           ["/etc/rc.d/40-" .. name .. ".lua"] = "-- service " .. name }
end

print("=== installing a service package needs root ===")
print()

do
  local pkg, fs = newPkg()
  local dir = putPkg(fs, "spy", serviceManifest("spy"), serviceBodies("spy"))
  local ok, err = pkg.install(dir, { session = ADMIN })
  test("an ADMIN cannot install a service package", not ok and tostring(err):find("root", 1, true) ~= nil)
  test("...and none of its files were written",
    fs._files["/usr/lib/spy.lua"] == nil and fs._files["/etc/rc.d/40-spy.lua"] == nil)
  test("...it is not registered", pkg.info("spy") == nil)

  local rok = pkg.install(dir, { session = ROOT })
  test("ROOT can install the same service package", rok == true)
  test("...and its rc.d entry is now on disk", fs._files["/etc/rc.d/40-spy.lua"] ~= nil)
  test("...and it is registered", pkg.info("spy") ~= nil)
end

do
  -- A command package runs sandboxed with its declared caps: ADMIN is enough.
  local pkg, fs = newPkg()
  local body = "return { commands = { tool = function() return 'ok' end } }"
  local dir = putPkg(fs, "tool", { name = "tool", version = "1.0.0", kind = "command",
    files = { "/usr/modules/tool/init.lua" } }, { ["/usr/modules/tool/init.lua"] = body })
  test("an ADMIN can still install a command package", pkg.install(dir, { session = ADMIN }) == true)
end

do
  -- ...and a driver (raw component access, but only the types its caps name,
  -- still inside the sandbox) stays ADMIN too.
  local pkg, fs = newPkg()
  local dir = putPkg(fs, "drv", { name = "drv", version = "1.0.0", kind = "driver",
    files = { "/usr/lib/drv.lua" }, capabilities = { "peripheral.modem" } },
    { ["/usr/lib/drv.lua"] = "return {}" })
  test("an ADMIN can install a driver package", pkg.install(dir, { session = ADMIN }) == true)
end

do
  -- An ADMIN must not be able to UPGRADE a command package into a service.
  local pkg, fs = newPkg()
  local d1 = putPkg(fs, "morph", { name = "morph", version = "1.0.0", kind = "command",
    files = { "/usr/modules/morph/init.lua" } }, { ["/usr/modules/morph/init.lua"] = "return {}" })
  test("ADMIN installs the command version", pkg.install(d1, { session = ADMIN }) == true)
  putPkg(fs, "morph", { name = "morph", version = "2.0.0", kind = "service",
    files = { "/usr/lib/morph.lua", "/etc/rc.d/40-morph.lua" } },
    { ["/usr/lib/morph.lua"] = "return {}", ["/etc/rc.d/40-morph.lua"] = "-- svc" })
  local ok, err = pkg.upgrade("morph", { session = ADMIN, extraRoots = { "/usr/repo" } })
  test("an ADMIN cannot upgrade it into a service", not ok and tostring(err):find("root", 1, true) ~= nil)
  test("...it is still the command version", pkg.info("morph").version == "1.0.0")
  test("ROOT can make that upgrade", pkg.upgrade("morph", { session = ROOT, extraRoots = { "/usr/repo" } }) == true)
end

do
  -- A service pulled in as a DEPENDENCY of a command is refused for an ADMIN:
  -- the nested install hits the same gate, and the whole batch rolls back.
  local pkg, fs = newPkg()
  putPkg(fs, "svcdep", serviceManifest("svcdep"), serviceBodies("svcdep"))
  putPkg(fs, "app", { name = "app", version = "1.0.0", kind = "command",
    files = { "/usr/modules/app/init.lua" }, requires = { "svcdep" } },
    { ["/usr/modules/app/init.lua"] = "return {}" })
  local ok = pkg.installWithDeps("/usr/repo", "app", { session = ADMIN })
  test("an ADMIN installing a command that needs a service is refused", not ok)
  test("...and nothing was left installed", pkg.info("app") == nil and pkg.info("svcdep") == nil)
  test("ROOT can install the pair", pkg.installWithDeps("/usr/repo", "app", { session = ROOT }) == true)
end

print()
print("-- the gate directly --")
do
  local pkg = newPkg()
  local g = pkg._serviceInstallGate
  local svc = { kind = "service" }
  test("a kernel/boot session may install a service (the installer)",
    g(svc, { session = { isKernel = true } }) == true)
  test("a login principal may NOT (guest-tier, adminGate lets it through)",
    g(svc, { session = { isLogin = true, tier = TIER.GUEST } }) == false)
  test("a non-service manifest is unaffected", g({ kind = "command" }, { session = ADMIN }) == true)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
