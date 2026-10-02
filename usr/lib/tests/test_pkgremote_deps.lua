-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `pkg fetch` brings what a package requires   ║
-- ║                                                                ║
-- ║  installRemote fetched one package and installed it with its   ║
-- ║  requirements unmet. It now stages the whole set from the      ║
-- ║  configured repos, resolves every requirement, and only then   ║
-- ║  installs -- dependencies first -- through the same door as a  ║
-- ║  hand-typed fetch. And a dependency NAME comes from a remote   ║
-- ║  manifest, so it is checked before it can become a path.       ║
-- ║                                                                ║
-- ║  Drives the REAL pkg.installRemote -> pkgremote.fetch ->        ║
-- ║  pkg.install chain over an in-memory disk and a fake card.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkgremote_deps.lua   (from TOS-Dev)

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

-- ── One machine ────────────────────────────────────────────────────
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
package.loaded["kernel.fs"] = F

-- ── A repo ─────────────────────────────────────────────────────────
local BASE = "https://r.example"
local SERVED, requests = {}, {}
package.loaded["kernel.internet"] = {
  available = function() return true end,
  status = function() return { ok = true } end,
  parseUrl = function() return true end,
  hostOf = function() return "r.example" end,
  get = function(url)
    requests[#requests + 1] = url
    if SERVED[url] then return SERVED[url] end
    return nil, "HTTP 404 Not Found", { status = 404, bytes = 0 }
  end,
  download = function(url, dest)
    requests[#requests + 1] = url
    local b = SERVED[url]; if not b then return false, "HTTP 404 Not Found" end
    F._f[dest] = b; return true, nil, { bytes = #b }
  end,
}
F._f["/etc/pkg-repos.cfg"] = serialize.encode({ { name = "r", url = BASE } })

local pkgsign = dofile("tos/kernel/pkgsign.lua")
pkgsign.init({ fs = F, serialize = serialize })
package.loaded["kernel.pkgsign"] = pkgsign
local pkgremote = dofile("tos/kernel/pkgremote.lua")
package.loaded["kernel.pkgremote"] = pkgremote
local pkg = dofile("tos/kernel/pkg.lua")
pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })

-- OPPM-style entries: one file in /usr/bin, hashed, with `dependencies`.
local INDEX = {}
local function oppm(name, deps, version)
  local body = "print('" .. name .. "')\n"
  SERVED[BASE .. "/" .. name .. ".lua"] = body
  INDEX[name] = { files = { [name .. ".lua"] = "/bin" }, version = version,
                  hashes = { ["/usr/bin/" .. name .. ".lua"] = sha.hex(body) }, dependencies = deps }
end
oppm("lib", nil, "1.0.0")
oppm("app", { lib = "/" }, "1.0.0")
oppm("needsnew", { lib = ">=2.0" }, "1.0.0")
oppm("orphan", { nothere = "/" })
oppm("evil", { ["../../tos"] = "/" })
oppm("cyca", { cycb = "/" })
oppm("cycb", { cyca = "/" })
for i = 1, 10 do oppm("deep" .. i, i < 10 and { ["deep" .. (i + 1)] = "/" } or nil) end

-- A native TOS package: its package.lua is one of the files, with requires.
do
  local body = "return 'tosapp'\n"
  local manifest = serialize.encode({
    name = "tosapp", version = "1.0.0", kind = "lib", description = "native package",
    files = { "/usr/lib/tosapp.lua" }, hashes = { ["/usr/lib/tosapp.lua"] = sha.hex(body) },
    capabilities = {},
    requires = { { name = "lib" }, { name = "neverfetched", optional = true } },
  })
  SERVED[BASE .. "/tosapp/package.lua"] = manifest           -- encode writes "return {...}"
  SERVED[BASE .. "/tosapp/usr/lib/tosapp.lua"] = body
  INDEX.tosapp = { files = { ["tosapp/package.lua"] = "/", ["tosapp/usr/lib/tosapp.lua"] = "/" } }
end
SERVED[BASE .. "/programs.cfg"] = serialize.encode(INDEX)

local function fetch(name)
  pkgremote.clearCache()
  requests = {}
  return pkg.installRemote(name, { session = ROOT, allowUnverified = true })
end
local function installed(n) return pkg.info(n) ~= nil end
local function asked(needle)
  local n = 0
  for _, u in ipairs(requests) do if u:find(needle, 1, true) then n = n + 1 end end
  return n
end
local function stagingLeft()
  for k in pairs(F._f) do
    if k:sub(1, #pkgremote.STAGE_ROOT + 1) == pkgremote.STAGE_ROOT .. "/" then return k end
  end
end
local function reset() for _, n in ipairs({ "app", "lib", "tosapp", "cyca", "cycb", "needsnew" }) do
  pcall(pkg.uninstall, n, { session = ROOT }) end end

print("=== pkg fetch brings what a package requires ===")
print()

local ok, res = fetch("app")
test("fetching a package that requires another installs both", ok == true and installed("app") and installed("lib"), res)
test("...dependency first, and the result names it",
  type(res) == "table" and res.dependencies and res.dependencies[1] == "lib")
test("...and staging is empty afterwards", stagingLeft() == nil, stagingLeft())

pcall(pkg.uninstall, "app", { session = ROOT })
ok = fetch("app")
test("an installed dependency that satisfies is not fetched again", ok == true and asked("/lib.lua") == 0)

ok, res = fetch("needsnew")
test("an installed dependency that is too old refuses, naming the fix",
  ok == false and not installed("needsnew") and tostring(res):find("pkg upgrade lib", 1, true) ~= nil, res)

reset()
ok, res = fetch("needsnew")
test("a repo copy that does not meet the constraint refuses",
  ok == false and tostring(res):find(">=2.0", 1, true) ~= nil and tostring(res):find("1.0.0", 1, true) ~= nil, res)
test("...and nothing at all is installed", not installed("needsnew") and not installed("lib"))
test("...and staging is empty", stagingLeft() == nil, stagingLeft())

ok, res = fetch("orphan")
test("a dependency no repo has refuses the fetch", ok == false and not installed("orphan"), res)
test("...naming it and what to do", tostring(res):find("'nothere'", 1, true) ~= nil
  and tostring(res):find("pkg install nothere", 1, true) ~= nil, res)

F._f["/tos/sentinel.lua"] = "the system"
ok, res = fetch("evil")
test("a dependency named like a path is refused before it is used", ok == false
  and tostring(res):find("not a package name", 1, true) ~= nil, res)
test("...and nothing outside staging was touched", F._f["/tos/sentinel.lua"] == "the system")
ok, res = fetch("../tos")
test("so is a typed one", ok == false and tostring(res):find("not a package name", 1, true) ~= nil, res)

ok, res = fetch("cyca")
test("two packages that require each other both install, once", ok == true and installed("cyca")
  and installed("cycb") and asked("/cyca.lua") == 1, res)

ok, res = fetch("deep1")
test("a chain deeper than the bound refuses", ok == false and tostring(res):find("deeper", 1, true) ~= nil, res)
test("...with nothing installed", not installed("deep1") and not installed("deep9"))

reset()
ok, res = fetch("tosapp")
test("a native package's requires (package.lua) are fetched too", ok == true and installed("tosapp") and installed("lib"), res)
test("...but an optional requirement is not", asked("neverfetched") == 0)
test("staging is empty after all of it", stagingLeft() == nil, stagingLeft())

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
