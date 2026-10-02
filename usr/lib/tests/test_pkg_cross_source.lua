-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: a dependency on another disk            ║
-- ║                                                            ║
-- ║  installWithDeps looked for dependencies in ONE root: the  ║
-- ║  one the target package came from. A package on floppy A   ║
-- ║  that needed a library on floppy B failed "unknown         ║
-- ║  package", with both disks in and pkg.findInRepos finding  ║
-- ║  the library -- and installByName's comment said it        ║
-- ║  resolved "across all available sources". Found scoping    ║
-- ║  federated repos (docs/FEDERATED-REPOS.md, finding 1).     ║
-- ║                                                            ║
-- ║  Pinned here: the other disk is searched; the target's own ║
-- ║  disk still wins; H-20 holds on every root; a floppy found ║
-- ║  only through the mount table counts.                      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_cross_source.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_cross_source.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

package.loaded["kernel.sha256"] = tryload("tos/kernel/sha256.lua")()
package.loaded["kernel.serialize"] = tryload("tos/kernel/serialize.lua")()
package.loaded["kernel.crypto"] = {
  hash = function(d) return package.loaded["kernel.sha256"].hex(d) end,
  ctEquals = function(a, b) return a == b end,
}
package.loaded["kernel.sandbox"] = { build = function() return {} end }
package.loaded["kernel.users"] = { currentSession = function() return nil end }

print("=== dependencies across sources Tests ===")
print()

-- ── A fake disk whose directories are implied by its files ───
local function makeFs(mounts)
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
  function F.mounts()
    local out = {}
    for _, mp in ipairs(mounts or {}) do out[#out + 1] = { mountPoint = mp } end
    return out
  end
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

-- A package directory: its manifest names itself `name` unless `claims`
-- says otherwise, and its one file carries `body` so the test can tell
-- which disk a copy came from.
local function put(F, root, dir, opts)
  opts = opts or {}
  local name = opts.claims or dir
  F._f[root .. "/" .. dir .. "/package.lua"] = string.format(
    'return { name = %q, version = %q, kind = "lib",\n'
    .. '  files = { "/usr/lib/%s.lua" }, requires = %s }\n',
    name, opts.version or "1.0.0", name, opts.requires or "nil")
  F._f[root .. "/" .. dir .. "/usr/lib/" .. name .. ".lua"] = opts.body or ("-- " .. root)
end

local function buildPkg(F)
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
  return pkg
end

local KERNEL = { isKernel = true }
local function install(pkg, name, extraRoots)
  return pkg.installByName(name, { extraRoots = extraRoots, session = KERNEL,
    allowUnverified = true })
end

-- ══════════════════════════════════════════════════════════════════════
print("-- the library is on the OTHER disk --")
do
  local F = makeFs()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/b", "lib")
  local pkg = buildPkg(F)
  local okI, res = install(pkg, "app", { "/x/a", "/x/b" })
  ok("app installs", okI == true)
  if not okI then print("      (" .. tostring(res) .. ")") end
  ok("and so does its library", pkg.info("lib") ~= nil)
  test("from the disk it is actually on", "-- /x/b", F._f["/usr/lib/lib.lua"])
  test("library first, then app", "lib,app",
    type(res) == "table" and table.concat(res.installed, ",") or nil)
end

print("-- a self-contained disk still uses its own copy --")
do
  local F = makeFs()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/x/a", "lib", { version = "1.0.0" })
  put(F, "/x/b", "lib", { version = "2.0.0" })
  local pkg = buildPkg(F)
  -- /x/b is listed FIRST, and still loses to the target's own disk.
  ok("app installs", (install(pkg, "app", { "/x/b", "/x/a" })))
  test("the library came from app's disk", "-- /x/a", F._f["/usr/lib/lib.lua"])
  test("at app's disk's version", "1.0.0", pkg.info("lib") and pkg.info("lib").version)
end

print("-- #SEC H-20 holds on every root --")
do
  local F = makeFs()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  -- A directory called `lib` whose manifest is something else entirely.
  put(F, "/x/b", "lib", { claims = "impostor", body = "-- impostor" })
  put(F, "/x/c", "lib")
  local pkg = buildPkg(F)
  ok("app installs", (install(pkg, "app", { "/x/a", "/x/b", "/x/c" })))
  test("the real library, from the next disk", "-- /x/c", F._f["/usr/lib/lib.lua"])
  test("the impostor installed nothing", nil, F._f["/usr/lib/impostor.lua"])
  test("and is not registered", nil, pkg.info("impostor"))
end

print("-- a library nowhere is still an error --")
do
  local F = makeFs()
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  local pkg = buildPkg(F)
  local okI, err = install(pkg, "app", { "/x/a" })
  test("app is refused", false, okI)
  ok("naming the missing library", tostring(err):find("unknown package: lib", 1, true) ~= nil)
  test("and nothing was installed", nil, pkg.info("app"))
end

print("-- a floppy known only from the mount table --")
do
  -- Boot-time mounts are virtual: in the mount table, not in /mnt's
  -- listing. That is the case the real two-floppy set hits.
  local F = makeFs({ "/mnt/disk2" })
  put(F, "/x/a", "app", { requires = '{ "lib" }' })
  put(F, "/mnt/disk2", "lib")
  local pkg = buildPkg(F)
  ok("app installs with no extra roots given", (install(pkg, "app", { "/x/a" })))
  test("its library came off the mounted floppy", "-- /mnt/disk2", F._f["/usr/lib/lib.lua"])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
