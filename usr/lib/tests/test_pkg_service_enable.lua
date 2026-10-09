-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: starting a service enables its package        ║
-- ║                                                                ║
-- ║  A service package that declares defaultState = "disabled"      ║
-- ║  (mail, intercom, cluster-master, cluster-manager) installs     ║
-- ║  with its rc.d boot marker AND its package byte off. `service   ║
-- ║  start` cleared only the marker, so a started service still     ║
-- ║  read "disabled" to `pkg list`, `pkg upgrade` said "(was        ║
-- ║  disabled; left disabled)" (headless machine, 2026-10-08), and  ║
-- ║  its programs never got the package's granted caps.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_service_enable.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_service_enable.lua"
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


print("=== starting a service enables its package ===")
print()

do
  local pkg, fs = newPkg()
  local bodies = {
    ["/usr/lib/svc.lua"]     = "return {}",
    ["/usr/bin/svc.lua"]     = "print('svc')",
    ["/etc/rc.d/svc.lua"]    = "-- service svc",
  }
  local dir = putPkg(fs, "svc", { name = "svc", version = "1.0.0", kind = "service",
    files = { "/usr/lib/svc.lua", "/usr/bin/svc.lua", "/etc/rc.d/svc.lua" },
    capabilities = { "net" },
    service = { defaultState = "disabled" } }, bodies)
  local ok, err = pkg.install(dir, { session = ROOT })
  test("the service package installs (" .. tostring(err) .. ")", ok)
  test("it installs disabled, as declared", pkg.isEnabled("svc") == false)
  test("...with the rc.d boot marker written", fs.exists("/etc/rc.d/svc.disabled"))
  test("ownerOfFile finds it whatever its state", pkg.ownerOfFile("/etc/rc.d/svc.lua") == "svc")
  test("its program gets no grant while it is disabled", pkg.capsForFile("/usr/bin/svc.lua") == nil)

  local USER = { user = "bob", tier = TIER.USER }
  test("a non-admin's start changes nothing",
    pkg.noteServiceStarted("svc", { session = USER }) == nil and pkg.isEnabled("svc") == false)

  test("starting it enables the package", pkg.noteServiceStarted("svc", { session = ADMIN }) == "svc")
  test("...which now reads enabled", pkg.isEnabled("svc") == true)
  local caps = pkg.capsForFile("/usr/bin/svc.lua")
  test("...and its program gets the package's caps", caps and caps.net == true)
  test("a second start reports nothing to change",
    pkg.noteServiceStarted("svc", { session = ADMIN }) == nil)

  test("a service no package ships changes nothing",
    pkg.noteServiceStarted("other", { session = ADMIN }) == nil)
  test("a name that would leave /etc/rc.d is refused",
    pkg.noteServiceStarted("../usr/lib/svc", { session = ADMIN }) == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
