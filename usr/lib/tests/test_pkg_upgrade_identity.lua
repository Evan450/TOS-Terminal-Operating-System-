-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: what an upgrade may replace a package    ║
-- ║  with                                                      ║
-- ║                                                            ║
-- ║  `pkg upgrade` ran every gate BEFORE removing the old      ║
-- ║  version except the signature gate, which only install()   ║
-- ║  runs -- after the removal. A candidate whose signature    ║
-- ║  did not verify deleted the working package and was then   ║
-- ║  refused, leaving neither installed. And it picked the     ║
-- ║  candidate by NAME, so a trusted package upgraded          ║
-- ║  silently to a stranger's, or to an unsigned one. Found    ║
-- ║  scoping federated repos (docs/FEDERATED-REPOS.md,         ║
-- ║  findings 2 and 3).                                        ║
-- ║                                                            ║
-- ║  Drives the real pkg, pkgsign and ed25519 against an       ║
-- ║  in-memory disk; every refusal is checked for the thing    ║
-- ║  that matters: the old version is still installed.         ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_upgrade_identity.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_upgrade_identity.lua"
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
package.loaded["kernel.sha512"] = tryload("tos/kernel/sha512.lua")()
local ed = tryload("tos/kernel/ed25519.lua")()
package.loaded["kernel.ed25519"] = ed
local serialize = tryload("tos/kernel/serialize.lua")()
package.loaded["kernel.serialize"] = serialize
package.loaded["kernel.crypto"] = {
  hash = function(d) return sha256.hex(d) end,
  ctEquals = function(a, b) return a == b end,
}
package.loaded["kernel.sandbox"] = { build = function() return {} end }
package.loaded["kernel.users"] = { currentSession = function() return nil end }

print("=== upgrade identity Tests ===")
print()

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local SEED_A, SEED_B = string.rep("A", 32), string.rep("B", 32)
local PUB_A, PUB_B = hex(ed.publickey(SEED_A)), hex(ed.publickey(SEED_B))

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

-- libx at `version` under root/libx, hashed, signed by `seed` (or not).
local function put(F, root, version, seed)
  local body = "return { v = " .. string.format("%q", version) .. " }"
  local m = string.format('return { name = "libx", version = %q, kind = "lib",\n'
    .. '  files = { "/usr/lib/libx.lua" },\n'
    .. '  hashes = { ["/usr/lib/libx.lua"] = %q } }\n', version, sha256.hex(body))
  F._f[root .. "/libx/package.lua"] = m
  F._f[root .. "/libx/usr/lib/libx.lua"] = body
  F._f[root .. "/libx/package.sig"] = nil
  if seed then
    local pub = ed.publickey(seed)
    F._f[root .. "/libx/package.sig"] = serialize.encode({ v = 1, alg = "ed25519",
      key = hex(pub), sig = hex(ed.sign(m, seed, pub)) })
  end
end

-- A machine that trusts publisher A and has libx 1.0.0 installed, signed
-- by A unless `installedSeed` says otherwise (false = unsigned).
local KERNEL = { isKernel = true }
local function machine(trust, installedSeed)
  if installedSeed == nil then installedSeed = SEED_A end
  local F = makeFs()
  F._f["/etc/pkg_trust.cfg"] = serialize.encode(trust or { keys = { alice = PUB_A } })
  package.loaded["kernel.pkgsign"] = nil
  local ps = tryload("tos/kernel/pkgsign.lua")()
  ps.init({ fs = F, serialize = serialize })
  package.loaded["kernel.pkgsign"] = ps
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
  put(F, "/x/old", "1.0.0", installedSeed or nil)
  local okI, err = pkg.installByName("libx", { extraRoots = { "/x/old" }, session = KERNEL })
  assert(okI, "setup install failed: " .. tostring(err))
  F.remove("/x/old")
  return pkg, F
end
local function upgrade(pkg, extra)
  local o = { extraRoots = { "/x/new" }, session = KERNEL }
  for k, v in pairs(extra or {}) do o[k] = v end
  return pkg.upgrade("libx", o)
end
local function stillOld(pkg, F, label)
  local m = pkg.info("libx")
  test(label .. ": 1.0.0 is still installed", "1.0.0", m and m.version)
  test(label .. ": and its file is still there", 'return { v = "1.0.0" }', F._f["/usr/lib/libx.lua"])
  test(label .. ": still recorded as alice's", "trusted", m and m._sigState)
end

-- ══════════════════════════════════════════════════════════════════════
print("-- control: the same publisher's next version --")
do
  local pkg, F = machine()
  put(F, "/x/new", "2.0.0", SEED_A)
  local okU, err = upgrade(pkg)
  ok("upgrades", okU == true)
  if not okU then print("      (" .. tostring(err) .. ")") end
  test("to 2.0.0", "2.0.0", pkg.info("libx") and pkg.info("libx").version)
  test("still trusted", "trusted", pkg.info("libx") and pkg.info("libx")._sigState)
end

print("-- a tampered candidate is refused BEFORE the old one is removed --")
do
  local pkg, F = machine()
  put(F, "/x/new", "2.0.0", SEED_A)
  -- Keep A's signature; change the manifest it covers.
  F._f["/x/new/libx/package.lua"] = F._f["/x/new/libx/package.lua"]
    :gsub('kind = "lib"', 'kind = "lib", description = "x"')
  local okU, err = upgrade(pkg)
  test("refused", false, okU)
  ok("as a signature that does not verify", tostring(err):find("does not verify", 1, true) ~= nil)
  ok("and not as a failure after removal", tostring(err):find("after removing", 1, true) == nil)
  stillOld(pkg, F, "tampered")
end

print("-- an unsigned candidate under `pkg trust require on` --")
do
  local pkg, F = machine({ requireSignature = true, keys = { alice = PUB_A } })
  put(F, "/x/new", "2.0.0", nil)
  local okU, err = upgrade(pkg)
  test("refused", false, okU)
  ok("because signatures are required", tostring(err):find("require signatures", 1, true) ~= nil)
  stillOld(pkg, F, "require on")
end

print("-- a stranger's candidate is refused (finding 2) --")
do
  local pkg, F = machine()
  put(F, "/x/new", "9.9.9", SEED_B)
  local okU, err = upgrade(pkg)
  test("refused", false, okU)
  ok("saying an upgrade does not change the publisher",
    tostring(err):find("does not change who publishes", 1, true) ~= nil)
  ok("naming the installed publisher by the operator's label",
    tostring(err):find("'alice'", 1, true) ~= nil)
  stillOld(pkg, F, "stranger")
end

print("-- an unsigned candidate is refused, require off --")
do
  local pkg, F = machine()
  put(F, "/x/new", "9.9.9", nil)
  local okU, err = upgrade(pkg)
  test("refused", false, okU)
  ok("as having no valid signature", tostring(err):find("no valid signature", 1, true) ~= nil)
  stillOld(pkg, F, "unsigned")
end

print("-- --force is the way through for a real key change --")
do
  local pkg, F = machine()
  put(F, "/x/new", "9.9.9", SEED_B)
  local okU, err = upgrade(pkg, { force = true })
  ok("upgrades", okU == true)
  if not okU then print("      (" .. tostring(err) .. ")") end
  local m = pkg.info("libx")
  test("to 9.9.9", "9.9.9", m and m.version)
  test("recorded honestly as an untrusted key", "unknown", m and m._sigState)
  test("B's key", PUB_B, m and m._sigKey)
end

print("-- an unsigned package may gain a signature --")
do
  local pkg, F = machine(nil, false)
  test("setup: installed unsigned", "unsigned", pkg.info("libx") and pkg.info("libx")._sigState)
  put(F, "/x/new", "2.0.0", SEED_A)
  ok("upgrades", (upgrade(pkg)) == true)
  test("now trusted", "trusted", pkg.info("libx") and pkg.info("libx")._sigState)
end

print("-- install() enforces an expected key on the bytes it reads --")
do
  local pkg, F = machine()
  ok("setup: uninstall", (pkg.uninstall("libx", { session = KERNEL })))
  put(F, "/x/new", "2.0.0", SEED_B)
  local okI, err = pkg.install("/x/new/libx", { session = KERNEL, expectKey = PUB_A })
  test("B's copy is refused when A's is expected", false, okI)
  ok("naming both keys' owners", tostring(err):find("'alice'", 1, true) ~= nil
    and tostring(err):find("an untrusted key", 1, true) ~= nil)
  test("and nothing was installed", nil, pkg.info("libx"))
  test("not even its file", nil, F._f["/usr/lib/libx.lua"])
  put(F, "/x/new", "2.0.0", SEED_A)
  ok("A's copy installs, the key compared case-blind",
    (pkg.install("/x/new/libx", { session = KERNEL, expectKey = PUB_A:upper() })) == true)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
