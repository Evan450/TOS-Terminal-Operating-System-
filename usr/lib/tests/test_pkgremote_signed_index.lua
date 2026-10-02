-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: an index signed as a whole stays signed      ║
-- ║                                                                ║
-- ║  A repo may sign its WHOLE programs.cfg (programs.sig beside   ║
-- ║  it). `pkg fetch` staged a re-encoded one-entry index and never ║
-- ║  downloaded the signature, so a package from a publisher this  ║
-- ║  machine trusts was recorded as `unsigned` -- and under `pkg   ║
-- ║  trust require on`, refused. The signed bytes and their        ║
-- ║  signature are now staged as a pair, and the package's entry   ║
-- ║  is taken from the bytes the signature covers.                 ║
-- ║                                                                ║
-- ║  Drives the REAL pkg.installRemote -> pkgremote.fetch ->        ║
-- ║  pkg.install chain with the REAL pkgsign and ed25519, a key    ║
-- ║  this test signs with, and a fake card serving a fake repo.    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkgremote_signed_index.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }
package.loaded["kernel.sandbox"] = { build = function() return {} end }
local ROOT = { tier = 3, user = "root" }
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 }, currentSession = function() return ROOT end }
-- ed25519 needs both hashers registered before it loads.
package.loaded["kernel.sha256"] = dofile("tos/kernel/sha256.lua")
package.loaded["kernel.sha512"] = dofile("tos/kernel/sha512.lua")
package.loaded["kernel.ed25519"] = dofile("tos/kernel/ed25519.lua")
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

-- ── A repo, served by a fake card ──────────────────────────────────
-- SERVED[url] is a body, or a function returning what internet.get would.
-- A miss answers as kernel.internet does: the status, in the error and meta.
local BASE = "https://r.example"
local SERVED = {}
local requests = {}
package.loaded["kernel.internet"] = {
  available = function() return true end,
  status = function() return { ok = true } end,
  parseUrl = function() return true end,
  hostOf = function() return "r.example" end,
  get = function(url)
    requests[#requests + 1] = url
    local b = SERVED[url]
    if type(b) == "function" then return b() end
    if b then return b end
    return nil, "HTTP 404 Not Found", { status = 404, bytes = 0 }
  end,
  download = function(url, dest)
    requests[#requests + 1] = url
    local b = SERVED[url]; if type(b) ~= "string" then return false, "HTTP 404 Not Found" end
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

local BODY = "print('app')\n"
local INDEX = serialize.encode({
  app = { files = { ["app.lua"] = "/bin" }, hashes = { ["/usr/bin/app.lua"] = sha.hex(BODY) },
          description = "a signed app" },
  other = { files = { ["other.lua"] = "/bin" } },
})
-- Sign the index the way a publisher would: real ed25519, seed from a
-- passphrase and label, the .sig beside the file it covers.
local seed = pkgsign.seedFromPassphrase("correct horse battery staple 42", "tester")
F._f["/sign/programs.cfg"] = INDEX
local keyHex = assert(pkgsign.signManifest("/sign/programs.cfg", seed, { signer = "tester" }))
local SIG = F._f["/sign/programs.sig"]
F.remove("/sign")

local function serve(index, sig)
  SERVED = { [BASE .. "/programs.cfg"] = index, [BASE .. "/app.lua"] = BODY }
  if sig then SERVED[BASE .. "/programs.sig"] = sig end
  pkgremote.clearCache()
  requests = {}
end
local function fetchApp()
  F._f["/usr/bin/app.lua"] = nil
  pcall(pkg.uninstall, "app", { session = ROOT })
  local ok, err = pkg.installRemote("app", { session = ROOT, allowUnverified = true })
  return ok, err, pkg.info("app")
end
local function sigAsks()
  local n = 0
  for _, u in ipairs(requests) do if u:find("programs.sig", 1, true) then n = n + 1 end end
  return n
end

print("=== an index signed as a whole stays signed ===")
print()

assert(pkgsign.addKey("tester", keyHex))
serve(INDEX, SIG)
local ok, err, info = fetchApp()
test("the signed index's package installs", ok == true)
if not ok then print("      (" .. tostring(err) .. ")") end
test("...recorded as signed by the trusted publisher", info and info._sigState == "trusted")
test("...under the publisher's label", info and info._sigLabel == "tester")
local leftover
for k in pairs(F._f) do
  if k:sub(1, #pkgremote.STAGE_ROOT + 1) == pkgremote.STAGE_ROOT .. "/" then leftover = k end
end
test("staging is cleared afterwards", leftover == nil)

-- The bytes must be the ones the signature covers.
serve(INDEX .. "\n-- appended\n", SIG)
ok, err, info = fetchApp()
test("an index that does not match its signature is refused", not ok and info == nil)
test("...and nothing is installed", F._f["/usr/bin/app.lua"] == nil)

-- Under `pkg trust require on` the signature is what lets it in at all.
pkgsign.setRequireSignature(true)
serve(INDEX, SIG)
ok = fetchApp()
test("with signatures required, the signed index is accepted", ok == true)
serve(INDEX, nil)
ok, err = fetchApp()
test("...and the same index unsigned is refused", not ok)
pkgsign.setRequireSignature(false)

-- The signature covers the index as it is NOW; the session's cached copy
-- may be older.
serve(INDEX, SIG)
assert(pkgremote.index(pkgremote.repos()[1]))
SERVED[BASE .. "/programs.cfg"] = function() return nil, "timed out after 10s with no data", { bytes = 0 } end
ok, err = fetchApp()
test("a signed index that cannot be re-read is refused",
  not ok and tostring(err):find("re-reading", 1, true) ~= nil)
serve(INDEX, SIG)
assert(pkgremote.index(pkgremote.repos()[1]))
SERVED[BASE .. "/programs.cfg"] = serialize.encode({ other = { files = { ["other.lua"] = "/bin" } } })
ok, err = fetchApp()
test("...and so is one the package has since left",
  not ok and tostring(err):find("no longer", 1, true) ~= nil)

-- A repo with no signature works as it always did.
print()
print("--- what counts as \"no signature\" ---")
serve(INDEX, nil)
ok, err, info = fetchApp()
test("an unsigned repo still installs", ok == true)
if not ok then print("      (" .. tostring(err) .. ")") end
test("...recorded as unsigned", info and info._sigState == "unsigned")
fetchApp()
test("...asking for a signature once a session", sigAsks() == 1)

-- A card without handle.response() cannot see a 404: the host's error
-- page arrives as the body. That is not a signature, and must not be
-- staged as a broken one -- that would refuse every unsigned repo.
serve(INDEX, function() return "404: Not Found" end)
ok, err, info = fetchApp()
test("an error page where the signature would be is no signature",
  ok == true and info and info._sigState == "unsigned")
serve(INDEX, function() return nil, "response exceeds the 4 KB limit", { status = 200, bytes = 5000 } end)
ok, err, info = fetchApp()
test("...nor is more than a signature could hold",
  ok == true and info and info._sigState == "unsigned")

-- Something that IS a signature, and a broken one, is evidence.
serve(INDEX, function() return "{ v = 1, alg = \"ed25519\" }" end)
ok, err, info = fetchApp()
test("a broken signature is refused, not called unsigned", not ok and info == nil)

-- No answer is not "none": guessing would record a signed package as
-- unsigned, the bug this fixes.
serve(INDEX, function() return nil, "timed out after 10s with no data", { bytes = 0 } end)
ok, err = fetchApp()
test("no answer about the signature refuses the fetch",
  not ok and tostring(err):find("whether it signs its index", 1, true) ~= nil)
SERVED[BASE .. "/programs.sig"] = SIG   -- the repo answers this time; no cache reset
ok, err, info = fetchApp()
test("...and the next fetch asks again", ok == true and info and info._sigState == "trusted")
serve(INDEX, function() return nil, "HTTP 503 Service Unavailable", { status = 503, bytes = 0 } end)
ok = fetchApp()
test("a server error is no answer either", not ok)
serve(INDEX, function() return nil, "HTTP 403 Forbidden", { status = 403, bytes = 0 } end)
ok, err, info = fetchApp()
test("a host that forbids the path has said there is none (S3 answers 403)",
  ok == true and info and info._sigState == "unsigned")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
