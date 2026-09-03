-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: signed package manifests                           ║
-- ║                                                            ║
-- ║  The mathematics is pinned by test_ed25519.lua against     ║
-- ║  RFC 8032. THIS file pins the policy, which is where the   ║
-- ║  security actually lives:                                  ║
-- ║    - four states, none of them silently another;           ║
-- ║    - an INVALID signature is a hard refusal with no        ║
-- ║      override, because degrading it to "unsigned" would    ║
-- ║      make corrupting a signature a way onto the permissive ║
-- ║      path;                                                 ║
-- ║    - a manifest cannot declare itself trusted;             ║
-- ║    - the publisher's self-declared name is never matched   ║
-- ║      against the trust store.                              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_signing.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_signing.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

package.loaded["kernel.sha512"] = tryload("tos/kernel/sha512.lua")()
package.loaded["kernel.sha256"] = tryload("tos/kernel/sha256.lua")()
local ed = tryload("tos/kernel/ed25519.lua")()
package.loaded["kernel.ed25519"] = ed

print("=== package signing Tests ===")
print()

-- ── A fake disk ──────────────────────────────────────────────
-- One in-memory filesystem shared by pkgsign and pkg, so the tests
-- exercise the same paths the real code walks.
local function makeFs(files)
  local F = { _f = files or {} }
  function F.exists(p) return F._f[p] ~= nil end
  function F.readFile(p) return F._f[p] end
  function F.writeFile(p, d) F._f[p] = d; return true end
  function F.remove(p) F._f[p] = nil; return true end
  function F.isDirectory() return true end
  function F.makeDirectory() return true end
  function F.list(p)
    if p == "/var/pkg/installed" then
      local out = {}
      for path in pairs(F._f) do
        local n = path:match("^/var/pkg/installed/([^/]+)/package%.lua$")
        if n then out[#out + 1] = n end
      end
      return out
    end
    return {}
  end
  function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
  function F.normalize(p) return (p:gsub("//+", "/"):gsub("/$", "")) end
  return F
end

-- The real serializer: signature and trust files are encoded and decoded
-- for real, so a shape the encoder cannot round-trip is a test failure
-- rather than a surprise on a live machine.
local serialize = tryload("tos/kernel/serialize.lua")()
package.loaded["kernel.serialize"] = serialize

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end

-- Two publishers.
local SEED_A = string.rep("A", 32)
local SEED_B = string.rep("B", 32)
local PUB_A  = hex(ed.publickey(SEED_A))
local PUB_B  = hex(ed.publickey(SEED_B))

local MANIFEST = 'return { name = "demo", version = "1.0.0", kind = "command",\n'
              .. '  files = { "/usr/modules/demo/init.lua" },\n'
              .. '  commands = { demo = "/usr/modules/demo/init.lua" },\n'
              .. '  capabilities = { "fs.read" } }\n'

local function newSign(files)
  local ps = tryload("tos/kernel/pkgsign.lua")()
  local F = makeFs(files)
  ps.init({ fs = F, serialize = serialize, log = nil })
  return ps, F
end

local function signRecord(seed, body, extra)
  local pub = ed.publickey(seed)
  local rec = { v = 1, alg = "ed25519", key = hex(pub),
                sig = hex(ed.sign(body, seed, pub)) }
  for k, v in pairs(extra or {}) do rec[k] = v end
  return serialize.encode(rec)
end

-- ══════════════════════════════════════════════════════════════════════
-- Signature paths
-- ══════════════════════════════════════════════════════════════════════
do
  local ps = newSign({})
  test("package.lua signs as package.sig", "/d/package.sig", ps.sigPathFor("/d/package.lua"))
  -- A repo index is signed the same way, which is the point of deriving
  -- the name instead of hard-coding "package.sig": one rule, four
  -- manifest forms.
  test("programs.cfg signs as programs.sig", "/r/programs.sig", ps.sigPathFor("/r/programs.cfg"))
  test("foo.cfg signs as foo.sig", "/d/foo.sig", ps.sigPathFor("/d/foo.cfg"))
end

-- ══════════════════════════════════════════════════════════════════════
-- The four states
-- ══════════════════════════════════════════════════════════════════════
do
  -- UNSIGNED: no signature file at all.
  local ps = newSign({ ["/d/package.lua"] = MANIFEST })
  local v = ps.verifyManifest("/d/package.lua")
  test("no signature file -> unsigned", "unsigned", v.state)
  ok("isVerified is false", not ps.isVerified(v))
  local desc = table.concat(ps.describe(v), " ")
  ok("and the description says admin privilege is the gate",
    desc:find("admin privilege") ~= nil)
end

do
  -- UNKNOWN: a real signature by a key nobody has trusted.
  local ps = newSign({
    ["/d/package.lua"] = MANIFEST,
    ["/d/package.sig"] = signRecord(SEED_A, MANIFEST),
  })
  local v = ps.verifyManifest("/d/package.lua")
  test("valid signature, untrusted key -> unknown", "unknown", v.state)
  test("the key is reported", PUB_A, v.key)
  ok("a fingerprint is offered", type(v.fingerprint) == "string" and #v.fingerprint > 0)
  -- This state is VERIFIED even though it is not trusted: the bytes
  -- really are from the holder of that key. Conflating it with unsigned
  -- would throw away the only thing the signature bought.
  ok("isVerified is true", ps.isVerified(v))
  local desc = table.concat(ps.describe(v), " ")
  ok("the description offers the trust command", desc:find("pkg trust add") ~= nil)
end

do
  -- TRUSTED: same signature, key in the store.
  local ps = newSign({
    ["/d/package.lua"] = MANIFEST,
    ["/d/package.sig"] = signRecord(SEED_A, MANIFEST),
    ["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { strata = PUB_A } }),
  })
  local v = ps.verifyManifest("/d/package.lua")
  test("trusted key -> trusted", "trusted", v.state)
  test("and names the OPERATOR's label", "strata", v.label)
  ok("isVerified is true", ps.isVerified(v))
end

do
  -- INVALID: the manifest was edited after signing. This is the whole
  -- point of the feature working.
  local ps = newSign({
    ["/d/package.lua"] = MANIFEST .. "-- one extra byte\n",
    ["/d/package.sig"] = signRecord(SEED_A, MANIFEST),
    ["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { strata = PUB_A } }),
  })
  local v = ps.verifyManifest("/d/package.lua")
  test("a tampered manifest -> invalid", "invalid", v.state)
  ok("isVerified is false", not ps.isVerified(v))
  local desc = table.concat(ps.describe(v), " ")
  ok("described as tampering, NOT as a missing signature",
    desc:find("tampering") ~= nil and desc:find("DOES NOT VERIFY") ~= nil)
end

do
  -- The key in the file signed a DIFFERENT manifest: right shape, wrong
  -- signer. Trusting A must not make B's package pass.
  local ps = newSign({
    ["/d/package.lua"] = MANIFEST,
    ["/d/package.sig"] = signRecord(SEED_B, MANIFEST),
    ["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { strata = PUB_A } }),
  })
  local v = ps.verifyManifest("/d/package.lua")
  test("another publisher's valid signature -> unknown, not trusted", "unknown", v.state)
  test("and reports THEIR key", PUB_B, v.key)
end

-- ══════════════════════════════════════════════════════════════════════
-- The name on the disk is not the identity
-- ══════════════════════════════════════════════════════════════════════
do
  -- A hostile disk signs with its own key and calls itself "strata".
  -- The label in the trust store belongs to a DIFFERENT key, so the
  -- verdict must be "unknown" — matching on the claimed name would be
  -- trusting a stranger for saying a word.
  local ps = newSign({
    ["/d/package.lua"] = MANIFEST,
    ["/d/package.sig"] = signRecord(SEED_B, MANIFEST, { signer = "strata" }),
    ["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { strata = PUB_A } }),
  })
  local v = ps.verifyManifest("/d/package.lua")
  test("a disk claiming a trusted name is still unknown", "unknown", v.state)
  test("no trusted label is attached", nil, v.label)
  test("the claim is carried, clearly as a claim", "strata", v.signer)
  local desc = table.concat(ps.describe(v), " ")
  ok("and shown as the disk's own word", desc:find("its own word, not proof") ~= nil)
end

-- ══════════════════════════════════════════════════════════════════════
-- Malformed signature files are INVALID, never absent
-- ══════════════════════════════════════════════════════════════════════
do
  local cases = {
    { "unparseable",       "this is not a lua table at all" },
    { "empty",             "" },
    { "no key",            serialize.encode({ alg = "ed25519", sig = string.rep("a", 128) }) },
    { "short key",         serialize.encode({ alg = "ed25519", key = "abcd", sig = string.rep("a", 128) }) },
    { "non-hex key",       serialize.encode({ alg = "ed25519", key = string.rep("z", 64), sig = string.rep("a", 128) }) },
    { "short signature",   serialize.encode({ alg = "ed25519", key = string.rep("a", 64), sig = "beef" }) },
    { "future algorithm",  serialize.encode({ alg = "dilithium", key = string.rep("a", 64), sig = string.rep("a", 128) }) },
  }
  for _, c in ipairs(cases) do
    local ps = newSign({ ["/d/package.lua"] = MANIFEST, ["/d/package.sig"] = c[2] })
    local v = ps.verifyManifest("/d/package.lua")
    -- Every one of these must be "invalid" and not "unsigned". If a
    -- broken signature read as unsigned, deleting or corrupting one
    -- would be a way to reach the permissive path.
    test("a " .. c[1] .. " signature file is INVALID", "invalid", v.state)
  end
end

do
  -- `covers` naming a different file is a refusal: otherwise a signature
  -- over some other manifest could be dropped next to this one.
  local ps = newSign({
    ["/d/package.lua"] = MANIFEST,
    ["/d/package.sig"] = signRecord(SEED_A, MANIFEST, { covers = "something-else.lua" }),
  })
  test("a signature covering another file is invalid", "invalid",
    ps.verifyManifest("/d/package.lua").state)
end

-- ══════════════════════════════════════════════════════════════════════
-- The trust store
-- ══════════════════════════════════════════════════════════════════════
do
  local ps, F = newSign({})
  test("no keys to begin with", 0, #ps.listKeys())
  ok("adding a key works", (ps.addKey("strata", PUB_A)))
  test("it is listed", 1, #ps.listKeys())
  test("under the operator's label", "strata", ps.listKeys()[1].label)
  test("and the key resolves back", "strata", ps.labelForKey(PUB_A))
  ok("it persisted to /etc/pkg_trust.cfg", F._f["/etc/pkg_trust.cfg"] ~= nil)

  -- Re-adding the same pair is idempotent; re-pointing a label at a
  -- different key is refused. Silent overwrite is how a trust store
  -- stops meaning what the operator thinks it means.
  ok("re-adding the same pair is fine", (ps.addKey("strata", PUB_A)))
  local okAdd, err = ps.addKey("strata", PUB_B)
  test("re-pointing a label is refused", false, okAdd)
  ok("and says to remove it first", tostring(err):find("remove it first") ~= nil)

  -- The same key under two names would make `pkg info` ambiguous.
  local okDup, dupErr = ps.addKey("strata2", PUB_A)
  test("the same key under a second label is refused", false, okDup)
  ok("and names the existing label", tostring(dupErr):find("strata") ~= nil)

  ok("removal works", (ps.removeKey("strata")))
  test("and it is gone", 0, #ps.listKeys())
  local okRm = ps.removeKey("strata")
  test("removing a key that is not there is refused", false, okRm)
end

do
  local ps = newSign({})
  local okAdd, err = ps.addKey("bad label!", PUB_A)
  test("a malformed label is refused", false, okAdd)
  ok("and says what is allowed", tostring(err):find("48") ~= nil)
  test("a malformed key is refused", false, (ps.addKey("x", "nothex")))
end

do
  -- A trust store that will not decode leaves NO keys in force. That is
  -- the safe direction: everything reads as unknown and needs the admin
  -- override, rather than something being trusted by accident.
  local ps = newSign({
    ["/d/package.lua"] = MANIFEST,
    ["/d/package.sig"] = signRecord(SEED_A, MANIFEST),
    ["/etc/pkg_trust.cfg"] = "{{{ not a table",
  })
  test("an undecodable trust store trusts nothing", 0, #ps.listKeys())
  test("so a signed package reads as unknown", "unknown",
    ps.verifyManifest("/d/package.lua").state)
end

do
  -- Junk entries are dropped individually rather than voiding the file.
  local ps = newSign({
    ["/etc/pkg_trust.cfg"] = serialize.encode({
      keys = { good = PUB_A, ["b a d"] = PUB_B, alsobad = "xyz" } }),
  })
  test("one good key survives junk beside it", 1, #ps.listKeys())
  test("and it is the good one", "good", ps.listKeys()[1].label)
end

do
  local ps = newSign({ ["/etc/pkg_trust.cfg"] = serialize.encode({ requireSignature = true, keys = {} }) })
  ok("requireSignature is read", ps.requiresSignature())
  local ps2 = newSign({})
  ok("and defaults to off", not ps2.requiresSignature())
end

-- ══════════════════════════════════════════════════════════════════════
-- Signing, on-box
-- ══════════════════════════════════════════════════════════════════════
do
  local ps, F = newSign({ ["/d/package.lua"] = MANIFEST })
  local seed, sErr = ps.seedFromPassphrase("short")
  test("a short signing passphrase is refused", nil, seed)
  ok("and says how long", tostring(sErr):find("12 characters") ~= nil)

  local good = ps.seedFromPassphrase("a properly long signing passphrase")
  test("a long one yields 32 bytes", 32, #good)
  -- Deterministic across machines, or a publisher could not sign from
  -- two computers.
  test("and is deterministic", good, ps.seedFromPassphrase("a properly long signing passphrase"))
  ok("a different passphrase gives a different key",
    good ~= ps.seedFromPassphrase("a properly long signing passphrasf"))

  local key, sigPath = ps.signManifest("/d/package.lua", good, { signer = "me" })
  ok("signing produces a key", type(key) == "string" and #key == 64)
  test("and writes the sig beside the manifest", "/d/package.sig", sigPath)
  ok("the file exists", F._f["/d/package.sig"] ~= nil)

  -- Round trip: what we just signed must verify, and must be attributed
  -- to the key we were told about.
  local v = ps.verifyManifest("/d/package.lua")
  test("the fresh signature verifies", "unknown", v.state)
  test("under the expected key", key, v.key)

  ok("trusting that key upgrades the verdict", (ps.addKey("me", key)))
  test("now trusted", "trusted", ps.verifyManifest("/d/package.lua").state)

  -- And one byte of drift breaks it.
  F._f["/d/package.lua"] = MANIFEST .. " "
  test("editing the manifest after signing invalidates it", "invalid",
    ps.verifyManifest("/d/package.lua").state)
end

-- ══════════════════════════════════════════════════════════════════════
-- pkg.install: the gate
-- ══════════════════════════════════════════════════════════════════════
local function buildPkg(files)
  local F = makeFs(files)
  package.loaded["kernel.pkgsign"] = nil
  local ps = tryload("tos/kernel/pkgsign.lua")()
  ps.init({ fs = F, serialize = serialize })
  package.loaded["kernel.pkgsign"] = ps
  package.loaded["kernel.crypto"] = {
    hash = function(d) return package.loaded["kernel.sha256"].hex(d) end,
    ctEquals = function(a, b) return a == b end,
  }
  package.loaded["kernel.sandbox"] = { build = function() return {} end }
  package.loaded["kernel.users"] = { currentSession = function() return nil end }
  local pkg = tryload("tos/kernel/pkg.lua")()
  pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
  return pkg, F, ps
end

-- pkg.install is admin-gated (#SEC CR-5). Every call here carries a
-- kernel session so the tests exercise the SIGNATURE gate rather than
-- bouncing off the privilege gate in front of it.
local ADMIN = { session = { isKernel = true } }
local function opts(extra)
  local o = { session = ADMIN.session }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local ENTRY = "return { commands = { demo = function() end } }"
local ENTRY_HASH = package.loaded["kernel.sha256"].hex(ENTRY)
local HASHED_MANIFEST =
  'return { name = "demo", version = "1.0.0", kind = "command",\n'
  .. '  files = { "/usr/modules/demo/init.lua" },\n'
  .. '  commands = { demo = "/usr/modules/demo/init.lua" },\n'
  .. '  hashes = { ["/usr/modules/demo/init.lua"] = "' .. ENTRY_HASH .. '" },\n'
  .. '  capabilities = { "fs.read" } }\n'

do
  -- Unsigned but hashed: installs, and the verdict is recorded honestly.
  local pkg, F = buildPkg({
    ["/media/demo/package.lua"] = HASHED_MANIFEST,
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
  })
  local okI, err = pkg.install("/media/demo", opts())
  ok("an unsigned, hashed package installs", okI == true or (okI and true))
  if not okI then print("      (" .. tostring(err) .. ")") end
  local m = pkg.info("demo")
  ok("it is installed", m ~= nil)
  test("and recorded as unsigned", "unsigned", m and m._sigState)
  local _ = F
end

do
  -- Signed by an untrusted key: still installs (the admin gate is the
  -- authority), and the key is recorded so `pkg info` can show it.
  local pkg = buildPkg({
    ["/media/demo/package.lua"] = HASHED_MANIFEST,
    ["/media/demo/package.sig"] = signRecord(SEED_A, HASHED_MANIFEST),
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
  })
  ok("a signed-by-unknown package installs", (pkg.install("/media/demo", opts())))
  local m = pkg.info("demo")
  test("recorded as unknown", "unknown", m and m._sigState)
  test("with the key kept", PUB_A, m and m._sigKey)
end

do
  -- Signed by a trusted key.
  local pkg = buildPkg({
    ["/media/demo/package.lua"] = HASHED_MANIFEST,
    ["/media/demo/package.sig"] = signRecord(SEED_A, HASHED_MANIFEST),
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
    ["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { strata = PUB_A } }),
  })
  ok("a trusted package installs", (pkg.install("/media/demo", opts())))
  local m = pkg.info("demo")
  test("recorded as trusted", "trusted", m and m._sigState)
  test("with the operator's label", "strata", m and m._sigLabel)
end

do
  -- THE ONE THAT MATTERS. A tampered manifest is refused outright,
  -- writes nothing, and cannot be overridden by any flag.
  local pkg, F = buildPkg({
    ["/media/demo/package.lua"] = HASHED_MANIFEST .. "-- tampered\n",
    ["/media/demo/package.sig"] = signRecord(SEED_A, HASHED_MANIFEST),
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
  })
  local okI, err = pkg.install("/media/demo", opts())
  test("a tampered signed package is REFUSED", false, okI)
  ok("and the refusal says tampering", tostring(err):find("tampering") ~= nil)
  ok("and says there is no override", tostring(err):find("no override") ~= nil)
  test("nothing was installed", nil, pkg.info("demo"))
  test("and no file was written", nil, F._f["/usr/modules/demo/init.lua"])

  -- Every escape hatch that exists for OTHER gates must not open this one.
  for _, flag in ipairs({ "allowUnverified", "allowUnsigned", "force" }) do
    local pkg2, F2 = buildPkg({
      ["/media/demo/package.lua"] = HASHED_MANIFEST .. "-- tampered\n",
      ["/media/demo/package.sig"] = signRecord(SEED_A, HASHED_MANIFEST),
      ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
    })
    test("--" .. flag .. " does not override a bad signature", false,
      (pkg2.install("/media/demo", opts({ [flag] = true }))))
    test("--" .. flag .. " wrote nothing", nil, F2._f["/usr/modules/demo/init.lua"])
  end
end

do
  -- requireSignature refuses unsigned packages outright.
  local pkg = buildPkg({
    ["/media/demo/package.lua"] = HASHED_MANIFEST,
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
    ["/etc/pkg_trust.cfg"] = serialize.encode({ requireSignature = true, keys = {} }),
  })
  local okI, err = pkg.install("/media/demo", opts())
  test("requireSignature refuses an unsigned package", false, okI)
  ok("and names the setting", tostring(err):find("require signatures") ~= nil)

  -- ...but this one IS overridable per-install: an operator who turned
  -- the policy on can still make a deliberate exception. Unlike a bad
  -- signature, an absent one is not evidence of anything.
  local pkg2 = buildPkg({
    ["/media/demo/package.lua"] = HASHED_MANIFEST,
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
    ["/etc/pkg_trust.cfg"] = serialize.encode({ requireSignature = true, keys = {} }),
  })
  ok("--allow-unsigned overrides the policy", (pkg2.install("/media/demo", opts({ allowUnsigned = true }))))
end

do
  -- A manifest cannot declare itself trusted. This is the shortest
  -- possible forgery and the fields are stripped on read.
  local forged = 'return { name = "demo", version = "1.0.0", kind = "command",\n'
    .. '  files = { "/usr/modules/demo/init.lua" },\n'
    .. '  commands = { demo = "/usr/modules/demo/init.lua" },\n'
    .. '  hashes = { ["/usr/modules/demo/init.lua"] = "' .. ENTRY_HASH .. '" },\n'
    .. '  _sigState = "trusted", _sigLabel = "strata", _sigKey = "' .. PUB_A .. '",\n'
    .. '  capabilities = { "fs.read" } }\n'
  local pkg = buildPkg({
    ["/media/demo/package.lua"] = forged,
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
  })
  ok("the forged manifest installs (nothing about it is invalid)", (pkg.install("/media/demo", opts())))
  local m = pkg.info("demo")
  test("but it is recorded as UNSIGNED, not trusted", "unsigned", m and m._sigState)
  test("and the forged label is gone", nil, m and m._sigLabel)
  test("and the forged key is gone", nil, m and m._sigKey)
end

do
  -- Signature and hashes are separate gates. A signed manifest that
  -- declares no hashes is still unverified code: the signature vouches
  -- for a manifest that promises nothing about the files.
  local pkg = buildPkg({
    ["/media/demo/package.lua"] = MANIFEST,
    ["/media/demo/package.sig"] = signRecord(SEED_A, MANIFEST),
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
    ["/etc/pkg_trust.cfg"] = serialize.encode({ keys = { strata = PUB_A } }),
  })
  local okI, err = pkg.install("/media/demo", opts())
  test("a trusted signature does not substitute for hashes", false, okI)
  ok("and the refusal is the hash one", tostring(err):find("unverified") ~= nil)
end

do
  -- pkg.checkSignature answers without installing — an operator should
  -- be able to ask who signed a floppy before deciding.
  local pkg, F = buildPkg({
    ["/media/demo/package.lua"] = HASHED_MANIFEST,
    ["/media/demo/package.sig"] = signRecord(SEED_A, HASHED_MANIFEST),
    ["/media/demo/usr/modules/demo/init.lua"] = ENTRY,
  })
  local v, m = pkg.checkSignature("/media/demo")
  test("checkSignature reports the state", "unknown", v and v.state)
  test("and the manifest", "demo", m and m.name)
  test("and installed nothing", nil, F._f["/usr/modules/demo/init.lua"])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
