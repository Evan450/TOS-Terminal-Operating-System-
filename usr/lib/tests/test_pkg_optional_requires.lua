-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: an optional requirement is optional      ║
-- ║                                                            ║
-- ║  `requires = { { name = "lib", optional = true } }` means  ║
-- ║  the package runs without lib. checkRequires has always    ║
-- ║  treated a missing optional one as met, but the resolver   ║
-- ║  visited it like any other, so the package could not be    ║
-- ║  installed at all unless lib was on some disk: "resolve    ║
-- ║  failed: unknown package: lib". Found while building the   ║
-- ║  federated-repos plan (docs/FEDERATED-REPOS.md).           ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_optional_requires.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_optional_requires.lua"
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

print("=== optional requires Tests ===")
print()

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
  function F.list() return {} end
  function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
  function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
  return F
end

local function put(F, root, name, requires)
  local body = "-- " .. name
  F._f[root .. "/" .. name .. "/package.lua"] = string.format(
    'return { name = %q, version = "1.0.0", kind = "lib",\n'
    .. '  files = { "/usr/lib/%s.lua" },\n'
    .. '  hashes = { ["/usr/lib/%s.lua"] = %q },\n'
    .. '  requires = %s }\n', name, name, name, sha256.hex(body), requires or "nil")
  F._f[root .. "/" .. name .. "/usr/lib/" .. name .. ".lua"] = body
end

local function machine()
  local F = makeFs()
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
  return pkg, F
end
local KERNEL = { isKernel = true }
local function install(pkg, name)
  return pkg.installByName(name, { extraRoots = { "/x/a", "/x/b" }, session = KERNEL })
end

print("-- an optional requirement available nowhere --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", '{ { name = "lib", optional = true } }')
  local okI, res = install(pkg, "app")
  ok("app installs without it", okI == true)
  if not okI then print("      (" .. tostring(res) .. ")") end
  test("lib is not installed", nil, pkg.info("lib"))
end

print("-- an optional requirement that IS available is installed --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", '{ { name = "lib", optional = true } }')
  put(F, "/x/b", "lib")
  ok("app installs", (install(pkg, "app")) == true)
  ok("and lib with it", pkg.info("lib") ~= nil)
end

print("-- a required one available nowhere is still an error --")
do
  local pkg, F = machine()
  put(F, "/x/a", "app", '{ "lib" }')
  local okI, err = install(pkg, "app")
  test("refused", false, okI)
  ok("as an unknown package", tostring(err):find("unknown package: lib", 1, true) ~= nil)
  test("app not installed", nil, pkg.info("app"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
