-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what `pkg fetch` may take from a repo nobody ║
-- ║  configured (federated repos slice 2, the floor)               ║
-- ║                                                                ║
-- ║  A requirement may name repos, and installed packages teach    ║
-- ║  the machine others (test_pkg_known_repos.lua). A fetch now    ║
-- ║  looks in those for what no configured repo has, and holds     ║
-- ║  what it finds to the floor in docs/FEDERATED-REPOS.md:        ║
-- ║    trusted key   -> installs                                   ║
-- ║    unknown key   -> the admin is shown the fingerprint and may ║
-- ║                     pin it, once; never a service or driver    ║
-- ║    unsigned / a signature that does not verify -> never        ║
-- ║  and `pkg trust discovered tofu|trusted|off` tightens it.      ║
-- ║  Drives the real pkg.installRemote -> pkgremote.fetch ->        ║
-- ║  pkg.install chain with real Ed25519 signatures, over an       ║
-- ║  in-memory disk and a fake internet card.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_discovered.lua   (from TOS-Dev)

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
function F.size(p) return F._f[p] and #F._f[p] or 0 end
function F.list(p) local out, seen = {}, {} for k in pairs(F._f) do if k:sub(1, #p + 1) == p .. "/" then local h = k:sub(#p + 2):match("^([^/]+)") if h and not seen[h] then seen[h] = true out[#out + 1] = h end end end return out end
function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
package.loaded["kernel.fs"] = F

-- ── Three repos, and a card that reaches them ──────────────────────
local CONF  = "https://conf.example/r"    -- the admin added this one
local HINT  = "https://hint.example/r"    -- a requirement names this one
local KNOWN = "https://known.example/r"   -- learned from an install
local SERVED, requests = {}, {}
package.loaded["kernel.internet"] = {
  available = function() return true end,
  status = function() return { ok = true } end,
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
local TPUB, UPUB = hex(ed.publickey(TSEED)), hex(ed.publickey(USEED))
local TRUST = "/etc/pkg_trust.cfg"
F._f[TRUST] = serialize.encode({ keys = { publisher = TPUB } })

local pkgsign = dofile("tos/kernel/pkgsign.lua")
pkgsign.init({ fs = F, serialize = serialize })
package.loaded["kernel.pkgsign"] = pkgsign
local pkgremote = dofile("tos/kernel/pkgremote.lua")
package.loaded["kernel.pkgremote"] = pkgremote
local pkg = dofile("tos/kernel/pkg.lua")
pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })

-- ── Packages ───────────────────────────────────────────────────────
local INDEX = { [CONF] = {}, [HINT] = {}, [KNOWN] = {} }
local function serve(base, name, opt)
  opt = opt or {}
  local body = "return '" .. name .. "@" .. base .. "'\n"
  local target = "/usr/lib/" .. name .. ".lua"
  local man = { name = name, version = opt.version or "1.0.0", kind = opt.kind or "lib",
    description = name, files = { target }, hashes = { [target] = sha.hex(body) },
    capabilities = {}, requires = opt.requires }
  local mbytes = serialize.encode(man)
  local files = { [name .. "/package.lua"] = "/", [name .. "/usr/lib/" .. name .. ".lua"] = "/" }
  if opt.seed then
    local pub = ed.publickey(opt.seed)
    SERVED[base .. "/" .. name .. "/package.sig"] = serialize.encode({ v = 1, alg = "ed25519",
      key = hex(pub), sig = hex(ed.sign(mbytes, opt.seed, pub)), covers = "package.lua",
      signer = opt.signer })
    files[name .. "/package.sig"] = "/"
  end
  if opt.tamper then mbytes = mbytes:gsub("1%.0%.0", "1.0.1") end   -- edited after signing
  SERVED[base .. "/" .. name .. "/package.lua"] = mbytes
  SERVED[base .. "/" .. name .. "/usr/lib/" .. name .. ".lua"] = body
  INDEX[base][name] = { files = files, version = man.version }
end

serve(HINT, "libt", { seed = TSEED })
serve(HINT, "libu", { seed = USEED, signer = "Totally Strata" })
serve(HINT, "libn")
serve(HINT, "svcu", { seed = USEED, kind = "service" })
serve(HINT, "libt2", { seed = TSEED })
serve(HINT, "libtamper", { seed = TSEED, tamper = true })
serve(HINT, "libc", { seed = TSEED })
serve(CONF, "libc")
serve(KNOWN, "libk", { seed = TSEED })
local function needs(name, dep, extra)
  local r = { name = dep, repos = { HINT } }
  for k, v in pairs(extra or {}) do r[k] = v end
  serve(CONF, name, { requires = { r } })
end
needs("app1", "libt")
needs("app2", "libu")
needs("app3", "libn")
needs("app4", "svcu")
needs("app5", "libt2", { key = UPUB })
needs("app6", "libx", { repos = { "ftp://bad.example/r" } })
needs("app7", "libtamper")
needs("appc", "libc")
for base, idx in pairs(INDEX) do SERVED[base .. "/programs.cfg"] = serialize.encode(idx) end

local function fetch(name, extra)
  pkgremote.clearCache()
  requests = {}
  local opts = { session = ROOT }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return pkg.installRemote(name, opts)
end
local function installed(n) return pkg.info(n) ~= nil end
local function asked(host)
  local n = 0
  for _, u in ipairs(requests) do if u:find(host, 1, true) then n = n + 1 end end
  return n
end
local function reset()
  for _, n in ipairs({ "app1", "app2", "app3", "app4", "app5", "app6", "app7", "appc",
      "libt", "libu", "libn", "svcu", "libt2", "libtamper", "libc", "libk" }) do
    pcall(pkg.uninstall, n, { session = ROOT })
  end
end
local function stagingLeft()
  for k in pairs(F._f) do
    if k:sub(1, #pkgremote.STAGE_ROOT + 1) == pkgremote.STAGE_ROOT .. "/" then return k end
  end
end

print("=== what pkg fetch may take from a repo nobody configured ===")
print()

-- ── The policy ─────────────────────────────────────────────────────
test("the default is trust-on-first-use", pkg.discoveredPolicy() == "tofu")

-- ── Signed by a trusted key ────────────────────────────────────────
local ok, res = fetch("app1")
test("a requirement in the repo it names, signed by a trusted key, installs",
  ok == true and installed("app1") and installed("libt"), res)
test("...after the configured repo was asked first", asked("conf.example/r/programs.cfg") >= 1)
test("...and the result names it", type(res) == "table" and res.dependencies and res.dependencies[1] == "libt")
test("...recorded as trusted", (pkg.info("libt") or {})._sigState == "trusted")
test("nothing is left in staging", stagingLeft() == nil, stagingLeft())
reset()

-- ── Signed by an unknown key: trust on first use ───────────────────
local calls, seenInfo = 0, nil
ok, res = fetch("app2", { confirmKey = function(info) calls = calls + 1; seenInfo = info; return "newpub" end })
test("an unknown key is shown to the admin, once", calls == 1)
test("...with the package, its requirer, the repo and the fingerprint",
  seenInfo and seenInfo.name == "libu" and seenInfo.by == "app2" and seenInfo.repo == HINT
  and seenInfo.fingerprint == pkgsign.fingerprint(UPUB) and seenInfo.key == UPUB)
test("...and the disk's own name for its publisher, as a claim", seenInfo and seenInfo.signer == "Totally Strata")
test("named, the key is trusted and the package installs",
  ok == true and installed("libu") and pkgsign.labelForKey(UPUB) == "newpub", res)
test("...as trusted", (pkg.info("libu") or {})._sigState == "trusted")
reset(); pkg.trustRemove("newpub", { session = ROOT })

calls = 0
ok, res = fetch("app2", { confirmKey = function() calls = calls + 1; return nil end })
test("refused at the prompt: nothing installs", ok == false and not installed("app2") and not installed("libu"))
test("...the key is not trusted", pkgsign.labelForKey(UPUB) == nil)
test("...and it says so", tostring(res):find("was not trusted", 1, true) ~= nil, res)

ok, res = fetch("app2")
test("with nobody to ask, an unknown key is refused", ok == false and not installed("libu"))
test("...with the way to trust it, and the dependency code",
  tostring(res):find("pkg trust add <name> " .. UPUB, 1, true) ~= nil
  and tostring(res):find("[E-603 ERR_PKG_DEPENDENCY]", 1, true) ~= nil, res)

calls = 0
ok, res = fetch("app4", { confirmKey = function() calls = calls + 1; return "x" end })
test("a SERVICE with an unknown key is refused without asking", ok == false and calls == 0
  and not installed("svcu"), res)
test("...because it runs outside the sandbox", tostring(res):find("runs outside the sandbox", 1, true) ~= nil, res)
test("...and no key was added", pkgsign.labelForKey(UPUB) == nil)

-- ── Unsigned, or a signature that does not verify ──────────────────
calls = 0
ok, res = fetch("app3", { allowUnsigned = true, allowUnverified = true,
  confirmKey = function() calls = calls + 1; return "x" end })
test("an unsigned package from there is refused, whatever the flags",
  ok == false and not installed("libn") and calls == 0, res)
test("...and the refusal says where unsigned packages may come from",
  tostring(res):find("only from a repo an admin added", 1, true) ~= nil, res)
ok, res = fetch("app7", { confirmKey = function() return "x" end })
test("a signature that does not verify is refused", ok == false and not installed("libtamper")
  and tostring(res):find("does not verify", 1, true) ~= nil, res)

-- ── A pin is held by install ───────────────────────────────────────
ok, res = fetch("app5", { confirmKey = function() return "x" end })
test("a requirement pinned to one key refuses a copy signed by another",
  ok == false and not installed("libt2") and not installed("app5"), res)

-- ── A configured repo always wins ──────────────────────────────────
ok, res = fetch("appc")
test("a requirement the configured repo has comes from there", ok == true and installed("libc"), res)
test("...and the repo it names is never asked", asked("hint.example") == 0)
reset()

-- ── Hints are held to the URL rule ─────────────────────────────────
ok, res = fetch("app6")
test("a hint that breaks the URL rule is never requested", ok == false and asked("bad.example") == 0, res)

-- ── A known repo, for a hand-typed fetch ───────────────────────────
pkgremote.learn({ KNOWN }, "someone")
ok, res = fetch("libk")
test("`pkg fetch` finds a package in a known repo", ok == true and installed("libk"), res)
test("...and says where it came from", type(res) == "table" and res.discovered == KNOWN, res and res.discovered)
reset()

-- ── Tightening it ──────────────────────────────────────────────────
test("only an admin may change the policy", pkg.trustDiscovered("off", { session = USER }) == false)
test("an unknown setting is refused", pkg.trustDiscovered("sometimes", { session = ROOT }) == false)
test("trusted: accepted", pkg.trustDiscovered("trusted", { session = ROOT }) == true
  and pkg.discoveredPolicy() == "trusted")
calls = 0
ok, res = fetch("app2", { confirmKey = function() calls = calls + 1; return "x" end })
test("trusted: an unknown key is refused without asking", ok == false and calls == 0
  and tostring(res):find("pkg trust discovered is trusted", 1, true) ~= nil, res)
ok = fetch("app1")
test("trusted: a trusted key still installs", ok == true and installed("libt"))
reset()

test("off: accepted", pkg.trustDiscovered("off", { session = ROOT }) == true)
ok, res = fetch("app1")
test("off: a requirement only elsewhere is not found", ok == false and not installed("libt")
  and tostring(res):find("not in any configured repo", 1, true) ~= nil, res)
test("off: the repo it names is never asked", asked("hint.example") == 0)
ok = fetch("libk")
test("off: known repos are not read either", ok == false and asked("known.example") == 0)
test("the setting is kept in the trust store", tostring(F._f[TRUST]):find('"off"', 1, true) ~= nil)
pkgsign.reloadTrust()
test("...and survives a reload", pkg.discoveredPolicy() == "off")

F._f[TRUST] = "return {"
pkgsign.reloadTrust()
test("a trust store that will not decode reads as off", pkg.discoveredPolicy() == "off")
F._f[TRUST] = serialize.encode({ keys = { publisher = TPUB }, discovered = "always" })
pkgsign.reloadTrust()
test("...and so does a setting this code does not know", pkg.discoveredPolicy() == "off")
F._f[TRUST] = serialize.encode({ keys = { publisher = TPUB } })
pkgsign.reloadTrust()
test("a store written before the setting existed reads as the default", pkg.discoveredPolicy() == "tofu")

-- ── Bounded ────────────────────────────────────────────────────────
F._f[pkgremote.KNOWN_CFG] = nil
local many = {}
for i = 1, 12 do many[i] = "https://m" .. i .. ".example/r" end
pkgremote.learn(many, "someone")
ok = fetch("nowhere")
local idxAsked = 0
for _, u in ipairs(requests) do if u:find("%.example/r/programs%.cfg$") and not u:find("conf.example", 1, true) then idxAsked = idxAsked + 1 end end
test("one lookup asks at most 8 repos nobody configured", ok == false and idxAsked == 8, idxAsked)

-- ── What the operator sees ─────────────────────────────────────────
do
  local f = io.open("tos/shell/panels/commands/admin.lua", "rb")
  local admin = f and f:read("*a"):gsub("\r\n", "\n") or ""
  if f then f:close() end
  test("`pkg trust discovered` exists", admin:find('act == "discovered"', 1, true) ~= nil)
  test("`pkg fetch` asks, and Enter refuses", admin:find("confirmKey = confirmKey", 1, true) ~= nil
    and admin:find("Name this publisher (Enter refuses): ", 1, true) ~= nil)
  -- The headless machine showed the question with nothing to compare:
  -- the panels shell draws a command's output when it ENDS. The
  -- fingerprint has to be in the box that asks.
  test("...with the fingerprint IN the box that asks, behind a typed word",
    admin:find('if not confirmTyped(msg, "trust"', 1, true) ~= nil
    and admin:find("tostring(info.fingerprint) .. \"\\n\"", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
