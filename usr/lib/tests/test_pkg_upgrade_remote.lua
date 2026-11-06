-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package from a repo can be updated         ║
-- ║                                                                ║
-- ║  `pkg outdated` looked at mounted disks only and `pkg upgrade` ║
-- ║  could not fetch, so a package installed with `pkg fetch` was  ║
-- ║  never offered a newer version: a fix to it never arrived.     ║
-- ║  Drives the real pkg.outdated -> pkg.upgradeRemote ->          ║
-- ║  pkgremote.fetch -> pkg.upgrade over a fake web, with real     ║
-- ║  Ed25519 signatures, as test_pkg_discovered.lua does.          ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_upgrade_remote.lua   (from TOS-Dev)

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
local USER = { tier = 1, user = "bob" }
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 }, currentSession = function() return ROOT end }
package.loaded["kernel.sha512"] = dofile("tos/kernel/sha512.lua")
package.loaded["kernel.sha256"] = dofile("tos/kernel/sha256.lua")
local ed = dofile("tos/kernel/ed25519.lua")
package.loaded["kernel.ed25519"] = ed
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = { hash = function(d) return sha.hex(d) end,
                                    ctEquals = function(a, b) return a == b end }

-- ── One machine ─────────────────────────────────────────────────
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
function F.size(p) return F._f[p] and #F._f[p] or 0 end
function F.list(p)
  local out, seen = {}, {}
  for k in pairs(F._f) do
    if k:sub(1, #p + 1) == p .. "/" then
      local rest = k:sub(#p + 2)
      local first = rest:match("^[^/]+")
      local isDir = rest:find("/", 1, true) ~= nil
      if first and not seen[first] then seen[first] = true; out[#out + 1] = first .. (isDir and "/" or "") end
    end
  end
  return out
end
function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
package.loaded["kernel.fs"] = F

-- ── One configured repo, one that is not, and a card that reaches them ──
local CONF  = "https://conf.example/r"
local OTHER = "https://other.example/r"
local SERVED, requests = {}, {}
local online = true
package.loaded["kernel.internet"] = {
  available = function() return online end,
  status = function() return { ok = online, reason = "no internet card" } end,
  parseUrl = function() return true end,
  hostOf = function(u) return u:match("^https?://([^/:]+)") end,
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
F._f["/etc/pkg-repos.cfg"] = serialize.encode({ { name = "conf", url = CONF } })

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local TSEED, USEED = string.rep("T", 32), string.rep("U", 32)
local TPUB = hex(ed.publickey(TSEED))
F._f["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { publisher = TPUB } })

local pkgsign = dofile("tos/kernel/pkgsign.lua")
pkgsign.init({ fs = F, serialize = serialize })
package.loaded["kernel.pkgsign"] = pkgsign
local pkgremote = dofile("tos/kernel/pkgremote.lua")
package.loaded["kernel.pkgremote"] = pkgremote
local pkg = dofile("tos/kernel/pkg.lua")
pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })

local INDEX = { [CONF] = {}, [OTHER] = {} }
local function serve(base, name, version, seed)
  local body = "return '" .. name .. " " .. version .. "'\n"
  local target = "/usr/lib/" .. name .. ".lua"
  local man = { name = name, version = version, kind = "lib", description = name,
    files = { target }, hashes = { [target] = sha.hex(body) }, capabilities = {} }
  local mbytes = serialize.encode(man)
  local files = { [name .. "/package.lua"] = "/", [name .. "/usr/lib/" .. name .. ".lua"] = "/" }
  SERVED[base .. "/" .. name .. "/package.sig"] = nil
  if seed then
    local pub = ed.publickey(seed)
    SERVED[base .. "/" .. name .. "/package.sig"] = serialize.encode({ v = 1, alg = "ed25519",
      key = hex(pub), sig = hex(ed.sign(mbytes, seed, pub)), covers = "package.lua" })
    files[name .. "/package.sig"] = "/"
  end
  SERVED[base .. "/" .. name .. "/package.lua"] = mbytes
  SERVED[base .. "/" .. name .. "/usr/lib/" .. name .. ".lua"] = body
  INDEX[base][name] = { files = files, version = version }
  SERVED[base .. "/programs.cfg"] = serialize.encode(INDEX[base])
  pkgremote.clearCache()
end
local function stagingLeft()
  for k in pairs(F._f) do
    if k:sub(1, #pkgremote.STAGE_ROOT + 1) == pkgremote.STAGE_ROOT .. "/" then return k end
  end
end
local function find(list, name)
  for _, u in ipairs(list) do if u.name == name then return u end end
end

print("=== a package from a repo is offered its update ===")
print()
serve(CONF, "liba", "1.0.0", TSEED)
local ok, err = pkg.installRemote("liba", { session = ROOT })
test("installed from the repo", ok == true and pkg.info("liba").version == "1.0.0", err)
test("nothing to offer while the repo has the same", find(pkg.outdated(), "liba") == nil)

serve(CONF, "liba", "1.1.0", TSEED)
local u = find(pkg.outdated(), "liba")
test("a newer version in the repo is listed", u and u.from == "1.0.0" and u.to == "1.1.0")
test("as the repo's, by name", u and u.remote == true and u.repo == "conf")

ok, err = pkg.upgradeRemote("liba", { session = ROOT })
test("pkg upgrade fetches it and upgrades", ok == true and pkg.info("liba").version == "1.1.0", err)
test("the new code is what landed", F._f["/usr/lib/liba.lua"] == "return 'liba 1.1.0'\n")
test("and the staging is gone", stagingLeft() == nil, stagingLeft())
test("now nothing is outdated", find(pkg.outdated(), "liba") == nil)

print()
print("=== what it does not do ===")
print()
online = false
requests = {}
serve(CONF, "liba", "1.2.0", TSEED)
test("with no card, outdated asks no repo", find(pkg.outdated(), "liba") == nil and #requests == 0)
online = true

test("remote = false keeps it to disks", find(pkg.outdated({ remote = false }), "liba") == nil)

serve(CONF, "liba", "1.3.0", USEED)
ok, err = pkg.upgradeRemote("liba", { session = ROOT })
test("an update signed by another publisher is refused", ok == false
  and tostring(err):find("E-611", 1, true) ~= nil, err)
test("and the old version stays", pkg.info("liba").version == "1.1.0")
test("and no staging is left", stagingLeft() == nil, stagingLeft())

serve(CONF, "liba", "1.4.0")
ok, err = pkg.upgradeRemote("liba", { session = ROOT })
test("so is one that is not signed at all", ok == false and pkg.info("liba").version == "1.1.0", err)

ok, err = pkg.upgradeRemote("liba", { session = USER })
test("an ordinary user may not upgrade", ok == false)

-- A repo nobody configured is held to the floor, which an upgrade does not
-- have, so it is never where an upgrade looks.
serve(CONF, "liba", "1.1.0", TSEED)
serve(OTHER, "liba", "9.0.0", TSEED)
F._f["/var/pkg/known-repos.cfg"] = serialize.encode({ { url = OTHER, from = "liba" } })
requests = {}
ok, err = pkg.upgradeRemote("liba", { session = ROOT })
local askedOther = false
for _, r in ipairs(requests) do if r:find("other.example", 1, true) then askedOther = true end end
test("a repo nobody configured is not asked", not askedOther)
test("and nothing came from it", pkg.info("liba").version == "1.1.0")

test("not installed is said so", select(2, pkg.upgradeRemote("nope", { session = ROOT }))
  :find("not installed", 1, true) ~= nil)
test("the operation loads on its own, as every other does", pkg._OPS_NAMES.upgradeRemote == true)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
