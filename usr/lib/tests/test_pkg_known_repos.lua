-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a package can say where it comes from, and   ║
-- ║  the machine LEARNS of those repos without trusting them       ║
-- ║                                                                ║
-- ║  Federated repos slice 2 (docs/FEDERATED-REPOS.md), first      ║
-- ║  part. A manifest may name `repos` for itself and, on a table- ║
-- ║  form requirement, for what it needs. Each is a URL this       ║
-- ║  machine may later request, so the rule is narrow. Installing  ║
-- ║  the package records them as KNOWN, in a store kept apart from ║
-- ║  /etc/pkg-repos.cfg: no install can add to the allowlist, and  ║
-- ║  a known repo is trusted with nothing (what a fetch may take   ║
-- ║  from one: test_pkg_discovered.lua). Drives the real           ║
-- ║  pkg.install, pkgremote and their validator.                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_known_repos.lua   (from TOS-Dev)

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
package.loaded["kernel.sha256"] = dofile("tos/kernel/sha256.lua")
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = { hash = function(d) return sha.hex(d) end,
                                    ctEquals = function(a, b) return a == b end }

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

package.loaded["kernel.internet"] = {
  available = function() return true end, status = function() return { ok = true } end,
  parseUrl = function() return true end,
  hostOf = function(u) return u:match("^https?://([^/:]+)") end,
  get = function() return nil, "HTTP 404 Not Found", { status = 404 } end,
}
F._f["/etc/pkg-repos.cfg"] = serialize.encode({ { name = "conf", url = "https://conf.example/oc" } })

local pkgsign = dofile("tos/kernel/pkgsign.lua")
pkgsign.init({ fs = F, serialize = serialize })
package.loaded["kernel.pkgsign"] = pkgsign
local pkgremote = dofile("tos/kernel/pkgremote.lua")
package.loaded["kernel.pkgremote"] = pkgremote
local pkg = dofile("tos/kernel/pkg.lua")
pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })

local function manifest(extra)
  local body = "return 'demo'\n"
  local m = { name = "demo", version = "1.0.0", kind = "lib", description = "d",
    files = { "/usr/lib/demo.lua" }, hashes = { ["/usr/lib/demo.lua"] = sha.hex(body) },
    capabilities = {} }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m, body
end
local function valid(extra) return pkg._validateManifest((manifest(extra))) end

print("=== a package names its repos; the machine learns of them ===")
print()

-- ── The URL rule ───────────────────────────────────────────────────
test("control: a manifest with no repos is valid", valid() == true)
for _, u in ipairs({ "https://r.example/oc/master", "http://host.example:8080/x",
                     "https://raw.githubusercontent.com/a/b/branch", "https://h.example" }) do
  test("accepted: " .. u, valid({ repos = { u } }) == true)
end
for _, u in ipairs({ "ftp://h.example/x", "https://u@h.example/x", "https://h.example/x?y=1",
                     "https://h.example/x#f", "https://h.example/../x", "https://h.example/a/./b",
                     "https://h.example\\x", "https://h.example/x y", "https://h.example/x\n",
                     "HTTPS://h.example/x", "https:///x", "https://.h/x", "https://h..e/x",
                     "https://h.example:123456/x", "https://h.example/" .. string.rep("a", 200) }) do
  local ok, why = valid({ repos = { u } })
  test("refused: " .. u:gsub("\n", "\\n"):sub(1, 50), ok == false
    and tostring(why):find("repos[1] is not an http(s) repo URL", 1, true) ~= nil, why)
end
local ok, why = valid({ repos = "https://h.example/x" })
test("repos must be an array", ok == false and tostring(why):find("array", 1, true) ~= nil, why)
ok, why = valid({ repos = { "https://a.e/1", "https://a.e/2", "https://a.e/3", "https://a.e/4", "https://a.e/5" } })
test("at most four repos", ok == false and tostring(why):find("more than 4", 1, true) ~= nil, why)
ok = valid({ repos = { "https://a.e/1", sneaky = "https://b.e/2" } })
test("a non-array key is refused, not skipped", ok == false)
test("a requirement may name repos", valid({ requires = { { name = "lib", repos = { "https://libs.e/x" } } } }) == true)
ok, why = valid({ requires = { { name = "lib", repos = { "ftp://x" } } } })
test("...held to the same rule", ok == false and tostring(why):find("requires[1].repos[1]", 1, true) ~= nil, why)
ok, why = valid({ requires = { { repos = { "https://libs.e/x" } } } })
test("...and it must name the package", ok == false and tostring(why):find("names repos but no package", 1, true) ~= nil, why)

-- ── Learning on install ────────────────────────────────────────────
local function install(name, extra)
  local m, body = manifest(extra)
  m.name = name
  m.files = { "/usr/lib/" .. name .. ".lua" }
  m.hashes = { ["/usr/lib/" .. name .. ".lua"] = sha.hex(body) }
  local dir = "/mnt/disk/" .. name
  F._f[dir .. "/package.lua"] = serialize.encode(m)
  F._f[dir .. "/usr/lib/" .. name .. ".lua"] = body
  return pkg.install(dir, { session = ROOT })
end
local function knownUrls()
  local out = {}
  for _, k in ipairs(pkg.knownRepos()) do out[#out + 1] = k.url end
  return table.concat(out, " ")
end

test("nothing is known before anything names a repo", #pkg.knownRepos() == 0)
local okI, iErr = install("demo", {
  repos = { "https://mirror.example/oc/", "https://conf.example/oc" },
  requires = { { name = "lib", optional = true, repos = { "https://libs.example/oc" } } },
})
test("a package naming repos installs", okI, iErr)
test("its repos are KNOWN: its own and its requirement's, in order",
  knownUrls() == "https://mirror.example/oc https://libs.example/oc", knownUrls())
test("...the configured repo is not repeated as known",
  not knownUrls():find("conf.example", 1, true))
test("...each says which package named it", pkg.knownRepos()[1].from[1] == "demo")
test("the allowlist is untouched", #pkg.repos() == 1 and pkg.repos()[1].name == "conf")

install("demo2", { repos = { "https://mirror.example/oc" } })
local k = pkg.knownRepos()
test("a repo named twice is one entry, from both", #k == 2
  and k[1].from[1] == "demo" and k[1].from[2] == "demo2", k[1] and table.concat(k[1].from, ","))

install("plain")
test("a package naming none changes nothing", #pkg.knownRepos() == 2)

-- ── The store reads back through the rule ──────────────────────────
F._f[pkgremote.KNOWN_CFG] = serialize.encode({
  { url = "https://ok.example/r", from = { "demo", "../../x" } },
  { url = "https://evil.example/x?redirect=1", from = { "demo" } },
  { url = 42 },
})
k = pkg.knownRepos()
test("an entry that breaks the URL rule is dropped on read", #k == 1 and k[1].url == "https://ok.example/r",
  knownUrls())
test("...and a `from` that is not a package name is dropped", #k[1].from == 1)

F._f[pkgremote.KNOWN_CFG] = nil
local many = {}
for i = 1, pkgremote.MAX_KNOWN + 8 do many[#many + 1] = "https://m" .. i .. ".example/r" end
pkgremote.learn(many, "demo")
k = pkg.knownRepos()
test("bounded: the newest " .. pkgremote.MAX_KNOWN .. " are kept", #k == pkgremote.MAX_KNOWN
  and k[#k].url == many[#many] and k[1].url == many[9], #k)

-- ── Forgetting ─────────────────────────────────────────────────────
local okF, n = pkg.forgetRepo(1, { session = ROOT })
test("forget by number", okF and n == 1 and #pkg.knownRepos() == pkgremote.MAX_KNOWN - 1)
okF = pkg.forgetRepo(many[#many], { session = ROOT })
test("forget by URL", okF and not knownUrls():find(many[#many], 1, true))
local okN, nWhy = pkg.forgetRepo("https://never.example/x", { session = ROOT })
test("forgetting what is not known says so", okN == false and tostring(nWhy):find("no known repo", 1, true) ~= nil)
local okU, uWhy = pkg.forgetRepo("all", { session = USER })
test("forgetting is an admin act", okU == false and tostring(uWhy):find("admin", 1, true) ~= nil, uWhy)
okF = pkg.forgetRepo("all", { session = ROOT })
test("forget all", okF and #pkg.knownRepos() == 0)

-- ── Without the rule, nothing passes ───────────────────────────────
do
  local bare = dofile("tos/kernel/pkgremote.lua")   -- never handed pkg's rule
  test("a pkgremote never given the rule learns nothing",
    bare.learn({ "https://fine.example/r" }, "demo") == 0)
  F._f[pkgremote.KNOWN_CFG] = serialize.encode({ { url = "https://fine.example/r", from = {} } })
  test("...and reads nothing back", #bare.known() == 0)
  F._f[pkgremote.KNOWN_CFG] = nil
end

-- ── What the operator sees ─────────────────────────────────────────
do
  local f = io.open("tos/shell/panels/commands/admin.lua", "rb")
  local admin = f and f:read("*a"):gsub("\r\n", "\n") or ""
  if f then f:close() end
  test("`pkg repo list` shows known repos apart, as not configured or trusted",
    admin:find("Known (named by installed packages; not trusted):", 1, true) ~= nil)
  test("`pkg repo forget` exists", admin:find('act == "forget"', 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
