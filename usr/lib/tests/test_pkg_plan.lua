-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: version contradictions, before a byte    ║
-- ║                                                            ║
-- ║  A version constraint was only ever a WARNING, and only     ║
-- ║  after the files were written: resolveInstallOrder skipped ║
-- ║  an installed dependency whatever its version, and         ║
-- ║  checkRequires reported "unmet requires" once the package  ║
-- ║  was down. `pkg upgrade` never asked whether the new       ║
-- ║  version broke an installed package that depends on it.    ║
-- ║  Found scoping federated repos (docs/FEDERATED-REPOS.md,   ║
-- ║  finding 4).                                               ║
-- ║                                                            ║
-- ║  Pinned here: pkg.plan finds each kind first; install and  ║
-- ║  upgrade refuse with who-needs-what and change nothing;    ║
-- ║  --force goes past; an upgrade is blocked only by what it  ║
-- ║  INTRODUCES, never by what was already wrong.              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_plan.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end
local function has(s, needle) return tostring(s):find(needle, 1, true) ~= nil end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_plan.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

local sha256 = tryload("tos/kernel/sha256.lua")()
package.loaded["kernel.sha256"] = sha256
package.loaded["kernel.serialize"] = tryload("tos/kernel/serialize.lua")()
package.loaded["kernel.crypto"] = {
  hash = function(d) return sha256.hex(d) end,
  ctEquals = function(a, b) return a == b end,
}
package.loaded["kernel.sandbox"] = { build = function() return {} end }
package.loaded["kernel.users"] = { currentSession = function() return nil end }

print("=== install plan Tests ===")
print()

-- ── A fake disk whose directories are implied by its files ───
local function makeFs()
  local F = { _f = {} }
  local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
  function F.exists(p)
    for k in pairs(F._f) do if under(p, k) then return true end end
    return false
  end
  function F.readFile(p) return F._f[p] end
  function F.writeFile(p, d) F._f[p] = d; return true end
  function F.remove(p)
    for k in pairs(F._f) do if under(p, k) then F._f[k] = nil end end
    return true
  end
  function F.isDirectory(p) return F.exists(p) and F._f[p] == nil end
  function F.makeDirectory() return true end
  function F.mounts() return {} end
  function F.list(p)
    local out, seen = {}, {}
    for k in pairs(F._f) do
      if k:sub(1, #p + 1) == p .. "/" then
        local head = k:sub(#p + 2):match("^([^/]+)")
        if head and not seen[head] then seen[head] = true; out[#out + 1] = head end
      end
    end
    return out
  end
  function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
  function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
  return F
end

-- A hashed, unsigned package at root/name. `requires` is Lua source.
local function put(F, root, name, version, requires)
  local body = "-- " .. name .. " " .. version .. " from " .. root
  F._f[root .. "/" .. name .. "/package.lua"] = string.format(
    'return { name = %q, version = %q, kind = "lib",\n'
    .. '  files = { "/usr/lib/%s.lua" },\n'
    .. '  hashes = { ["/usr/lib/%s.lua"] = %q },\n'
    .. '  requires = %s }\n', name, version, name, name, sha256.hex(body), requires or "nil")
  F._f[root .. "/" .. name .. "/usr/lib/" .. name .. ".lua"] = body
end

local KERNEL = { isKernel = true }
local ROOTS = { "/x/a", "/x/b", "/x/c" }
local function machine()
  local F = makeFs()
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
  return pkg, F
end
local function opts(extra)
  local o = { extraRoots = ROOTS, session = KERNEL }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end
local function install(pkg, name, extra) return pkg.installByName(name, opts(extra)) end
-- Install `name` from a scratch root that is then removed, so later
-- lookups cannot find it on a disk.
local function preinstall(pkg, F, name, version, requires)
  put(F, "/tmp/seed", name, version, requires)
  local okI, err = pkg.installByName(name, { extraRoots = { "/tmp/seed" }, session = KERNEL })
  assert(okI, "setup: " .. name .. ": " .. tostring(err))
  F.remove("/tmp/seed")
end
local function version(pkg, name) local m = pkg.info(name); return m and m.version end
local function kinds(plan)
  local out = {}
  for _, c in ipairs(plan and plan.contradictions or {}) do out[#out + 1] = c.kind end
  return table.concat(out, ",")
end

-- ══════════════════════════════════════════════════════════════════════
print("-- control: a consistent install plans clean --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", "1.0.0", '{ "lib >=1.0" }')
  put(F, "/x/a", "lib", "1.2.0")
  local plan = pkg.plan("/x/a", "app", opts())
  test("no contradictions", "", kinds(plan))
  ok("installs", (install(pkg, "app")) == true)
end

print("-- an installed dependency at the wrong version --")
do
  local pkg, F = machine()
  preinstall(pkg, F, "lib", "1.0.0")
  put(F, "/x/a", "app", "1.0.0", '{ "lib >=2.0" }')
  local plan = pkg.plan("/x/a", "app", opts())
  test("the plan finds it", "version", kinds(plan))
  local okI, err = install(pkg, "app")
  test("install refuses", false, okI)
  ok("saying who needs what", has(err, "app requires 'lib' >=2.0, and the installed lib is 1.0.0"))
  test("app was not written", nil, F._f["/usr/lib/app.lua"])
  ok("--force goes past it", (install(pkg, "app", { force = true })) == true)
end

print("-- a copy that satisfies the constraint beats the target's own disk --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", "1.0.0", '{ "lib ^2.0" }')
  put(F, "/x/a", "lib", "1.0.0")       -- first in line, too old
  put(F, "/x/b", "lib", "2.1.0")
  ok("installs", (install(pkg, "app")) == true)
  test("lib 2.1.0 from the other disk", "2.1.0", version(pkg, "lib"))
end

print("-- no copy anywhere satisfies it --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", "1.0.0", '{ "lib ^2.0" }')
  put(F, "/x/a", "lib", "1.0.0")
  local okI, err = install(pkg, "app")
  test("refused", false, okI)
  ok("naming the copy found", has(err, "app requires 'lib' ^2.0, and the copy in /x/a/lib is 1.0.0"))
  test("nothing installed", nil, pkg.info("lib"))
end

print("-- two packages in one install need incompatible versions --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", "1.0.0", '{ "lib >=2.0", "helper" }')
  put(F, "/x/a", "helper", "1.0.0", '{ "lib <2.0" }')
  put(F, "/x/a", "lib", "2.1.0")
  local okI, err = install(pkg, "app")
  test("refused", false, okI)
  ok("naming the one the chosen copy fails", has(err, "helper requires 'lib' <2.0, and the copy in /x/a/lib is 2.1.0"))
  test("helper not installed", nil, pkg.info("helper"))
  test("lib not installed", nil, pkg.info("lib"))
end

print("-- installing a package an installed one needs at another version --")
do
  local pkg, F = machine()
  -- mail wants lib ^3.0 but can run without it: it went in with lib 3.0,
  -- and lib has since been removed (an optional requirement does not
  -- hold an uninstall back).
  put(F, "/tmp/seed", "lib", "3.0.0")
  preinstall(pkg, F, "mail", "1.0.0", '{ { name = "lib", version = "^3.0", optional = true } }')
  assert(pkg.uninstall("lib", { session = KERNEL }))
  put(F, "/x/a", "lib", "2.0.0")
  local plan = pkg.plan("/x/a", "lib", opts())
  test("the plan finds it", "breaks", kinds(plan))
  local okI, err = install(pkg, "lib")
  test("install refuses", false, okI)
  ok("saying what it would break", has(err, "the installed mail requires 'lib' ^3.0, and the lib being put in is 2.0.0"))
  test("lib not installed", nil, pkg.info("lib"))
end

print("-- an upgrade that breaks an installed dependent --")
do
  local pkg, F = machine()
  preinstall(pkg, F, "lib", "1.5.0")
  preinstall(pkg, F, "app", "1.0.0", '{ "lib <2.0" }')
  put(F, "/x/b", "lib", "2.1.0")
  local okU, err = pkg.upgrade("lib", opts())
  test("refused", false, okU)
  ok("saying who it would break", has(err, "the installed app requires 'lib' <2.0, and the lib being put in is 2.1.0"))
  test("lib is still 1.5.0", "1.5.0", version(pkg, "lib"))
  ok("--force goes past it", (pkg.upgrade("lib", opts({ force = true }))) == true)
  test("to 2.1.0", "2.1.0", version(pkg, "lib"))
end

print("-- an upgrade whose new requirements are not met --")
do
  local pkg, F = machine()
  preinstall(pkg, F, "core", "2.0.0")
  preinstall(pkg, F, "lib", "1.0.0", '{ "core" }')
  put(F, "/x/b", "lib", "2.0.0", '{ "core >=3.0", "newdep" }')
  local okU, err = pkg.upgrade("lib", opts())
  test("refused", false, okU)
  ok("a dependency too old", has(err, "lib 2.0.0 requires 'core' >=3.0, and the installed core is 2.0.0"))
  ok("and one missing", has(err, "lib 2.0.0 requires 'newdep', which is not installed (install it first)"))
  test("lib is still 1.0.0", "1.0.0", version(pkg, "lib"))
end

print("-- an upgrade is not blocked by what was already wrong --")
do
  local pkg, F = machine()
  preinstall(pkg, F, "core", "2.0.0")
  -- Installed already needing core >=3 -- past the check, as before.
  put(F, "/tmp/seed", "lib", "1.0.0", '{ "core >=3.0" }')
  assert(pkg.installByName("lib", { extraRoots = { "/tmp/seed" }, session = KERNEL, force = true }))
  F.remove("/tmp/seed")
  put(F, "/x/b", "lib", "1.1.0", '{ "core >=3.0" }')
  local okU, err = pkg.upgrade("lib", opts())
  ok("upgrades: it makes nothing worse", okU == true)
  if not okU then print("      (" .. tostring(err) .. ")") end
  test("to 1.1.0", "1.1.0", version(pkg, "lib"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
