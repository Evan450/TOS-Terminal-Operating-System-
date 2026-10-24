-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: trust.lua's automatic Diffie-Hellman         ║
-- ║                                                              ║
-- ║  Area 1 of the user's redesign request: two TOS peers should    ║
-- ║  get a shared secret with no operator action beyond the trust   ║
-- ║  decision they already make (elevating to TRUSTED). Covers:     ║
-- ║  the DH identity persisting across a reload, the trust.dat       ║
-- ║  format migration (old bare-peer-map files still load), both     ║
-- ║  real triggers (note-then-elevate and elevate-then-note) landing  ║
-- ║  on the SAME secret two independent peers derive, that an         ║
-- ║  existing (manual/paired) secret is never overwritten, and that    ║
-- ║  a broken randomness source degrades to "no secret yet" rather      ║
-- ║  than a crash.                                                      ║
-- ║                                                              ║
-- ║  trust.lua keeps its state in module-level locals (peers, myDh),     ║
-- ║  so a real require() would hand every "peer" in this file the SAME    ║
-- ║  singleton -- loadfile()() gives each side its own, the same          ║
-- ║  technique test_ed25519.lua/test_x25519.lua use for their own          ║
-- ║  kernel modules.                                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_trust_dh.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
-- trust.lua requires "computer" (OC's global) at load time; stub it.
package.loaded["computer"] = { uptime = function() return 0 end }

local function freshTrust()
  return assert(loadfile("tos/kernel/net/trust.lua"))()
end

-- In-memory fs, shared shape with the rest of this test suite.
local function fsStub()
  local files = {}
  return {
    exists = function(p) return files[p] ~= nil end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, data) files[p] = data; return true end,
    writeFileAtomic = function(p, data) files[p] = data; return true end,
  }, files
end

-- A fake crypto with just what trust.lua's DH path needs: salt(n) for
-- randomness. Deterministic per instance (not per call) so two
-- different fakeCrypto() instances give two different -- but each
-- internally stable -- DH identities, without needing real hardware or
-- crypto.init().
local function fakeCrypto(letter)
  return { salt = function(n) return string.rep(letter, n) end }
end

-- A crypto whose randomness source is broken, the way a box with
-- neither a data card nor a seeded software pool might behave.
local function brokenCrypto()
  return { salt = function() error("no entropy source") end }
end

local ADMIN_ACTOR, ADMIN_TIER = "root", 2
local ADDR_A = "aaaaaaaa-1111-1111-1111-111111111111"
local ADDR_B = "bbbbbbbb-2222-2222-2222-222222222222"

print("=== trust.lua: automatic Diffie-Hellman Tests ===")
print()

-- ── getMyDhPublicKey: generated once, stable, persists across reload ─
do
  local fs = fsStub()
  local t1 = freshTrust()
  t1.init({ fs = fs, crypto = fakeCrypto("A") })
  local pub1 = t1.getMyDhPublicKey()
  test("a DH public key is generated", pub1 ~= nil)
  eq("...and it is 32 bytes", 32, pub1 and #pub1)
  eq("...stable across a second call", pub1, t1.getMyDhPublicKey())

  -- Simulate a reboot: a fresh instance over the SAME on-disk state.
  local t2 = freshTrust()
  t2.init({ fs = fs, crypto = fakeCrypto("A") })
  eq("...and stable across a reload from the same file", pub1, t2.getMyDhPublicKey())
end

-- ── Old trust.dat format (bare peer map) still loads ────────────────
do
  local fs, files = fsStub()
  local serialize = require("kernel.serialize")
  files["/etc/trust.dat"] = serialize.encode({
    [ADDR_A] = { level = 2, hostname = "old-peer", firstSeen = 1, lastSeen = 2 },
  })
  local t = freshTrust()
  t.init({ fs = fs, crypto = fakeCrypto("A") })
  eq("a peer from the pre-DH format is still read", "old-peer",
    (t.getPeer(ADDR_A) or {}).hostname)
  eq("...at its saved trust level", 2, t.getLevel(ADDR_A))
  test("no DH identity existed in the old file, so one is generated fresh",
    t.getMyDhPublicKey() ~= nil)
end

-- ── Two independent peers derive the SAME secret, triggered either way ─
for _, order in ipairs({ "note-then-elevate", "elevate-then-note" }) do
  local a = freshTrust()
  a.init({ fs = (fsStub()), crypto = fakeCrypto("A") })
  local b = freshTrust()
  b.init({ fs = (fsStub()), crypto = fakeCrypto("B") })

  local pubA, pubB = a.getMyDhPublicKey(), b.getMyDhPublicKey()
  test("[" .. order .. "] A and B generated DIFFERENT identities", pubA ~= pubB)

  a.setLevel(ADMIN_ACTOR, ADDR_B, 2, ADMIN_TIER)   -- A trusts B
  b.setLevel(ADMIN_ACTOR, ADDR_A, 2, ADMIN_TIER)   -- B trusts A

  if order == "note-then-elevate" then
    -- Already covered by the setLevel calls above (both already TRUSTED
    -- before noting) -- so instead exercise the elevate-at-UNKNOWN,
    -- note-while-KNOWN-but-not-yet-TRUSTED, elevate-last path cleanly:
    -- start over with level KNOWN first.
    a.setLevel(ADMIN_ACTOR, ADDR_B, 1, ADMIN_TIER)  -- back down to KNOWN
    b.setLevel(ADMIN_ACTOR, ADDR_A, 1, ADMIN_TIER)
    a.noteDhPublicKey(ADDR_B, pubB)   -- cached while B is only KNOWN
    b.noteDhPublicKey(ADDR_A, pubA)
    test("[" .. order .. "] no secret yet (peer not TRUSTED)",
      (a.getPeer(ADDR_B) or {}).sharedSecret == nil)
    a.setLevel(ADMIN_ACTOR, ADDR_B, 2, ADMIN_TIER)  -- NOW elevate to TRUSTED
    b.setLevel(ADMIN_ACTOR, ADDR_A, 2, ADMIN_TIER)
  else
    -- Already TRUSTED (from the setLevel calls above); noting the key
    -- now is the trigger.
    a.noteDhPublicKey(ADDR_B, pubB)
    b.noteDhPublicKey(ADDR_A, pubA)
  end

  local peerA, peerB = a.getPeer(ADDR_B), b.getPeer(ADDR_A)
  test("[" .. order .. "] A now has a secret for B", peerA and peerA.sharedSecret ~= nil)
  test("[" .. order .. "] B now has a secret for A", peerB and peerB.sharedSecret ~= nil)

  -- getPeer() doesn't expose the raw secret (by design -- see
  -- _internalGetSecret's token gate); read it the same privileged way
  -- an admin command would, to prove the two sides actually AGREE.
  local secretA = a.getSecret(ADMIN_ACTOR, ADDR_B, ADMIN_TIER)
  local secretB = b.getSecret(ADMIN_ACTOR, ADDR_A, ADMIN_TIER)
  test("[" .. order .. "] both sides derived a secret", secretA and secretB)
  eq("[" .. order .. "] ...and it's the SAME secret, not just present on both",
    secretA, secretB)
end

-- ── Never overwrites an existing (manual/paired) secret ─────────────
do
  local a = freshTrust()
  a.init({ fs = (fsStub()), crypto = fakeCrypto("A") })
  local b = freshTrust()
  b.init({ fs = (fsStub()), crypto = fakeCrypto("B") })
  a.setLevel(ADMIN_ACTOR, ADDR_B, 2, ADMIN_TIER)

  local manual = "this-secret-was-set-by-the-operator-not-dh!!"
  local okSet = a.setSecret(ADMIN_ACTOR, ADDR_B, manual, ADMIN_TIER)
  test("manual secret set", okSet)

  a.noteDhPublicKey(ADDR_B, b.getMyDhPublicKey())
  eq("DH never overwrites a secret that was already set",
    manual, a.getSecret(ADMIN_ACTOR, ADDR_B, ADMIN_TIER))
end

-- ── Broken randomness: degrades to "no secret yet", never a crash ───
do
  local a = freshTrust()
  a.init({ fs = (fsStub()), crypto = brokenCrypto() })
  local b = freshTrust()
  b.init({ fs = (fsStub()), crypto = fakeCrypto("B") })
  a.setLevel(ADMIN_ACTOR, ADDR_B, 2, ADMIN_TIER)

  test("a broken randomness source yields no public key, not an error",
    a.getMyDhPublicKey() == nil)
  local okN = pcall(a.noteDhPublicKey, ADDR_B, b.getMyDhPublicKey())
  test("noteDhPublicKey doesn't raise even with a broken local identity", okN)
  local peer = a.getPeer(ADDR_B)
  test("...and the peer simply has no secret yet (the existing #47 refusal "
    .. "in net.send is the graceful fallback)", peer and peer.sharedSecret == nil)
end

-- ── noteDhPublicKey: malformed input is ignored, not trusted blindly ─
do
  local a = freshTrust()
  a.init({ fs = (fsStub()), crypto = fakeCrypto("A") })
  a.setLevel(ADMIN_ACTOR, ADDR_B, 2, ADMIN_TIER)
  local okN1 = pcall(a.noteDhPublicKey, ADDR_B, "too short")
  test("a too-short key doesn't raise", okN1)
  local okN2 = pcall(a.noteDhPublicKey, ADDR_B, 12345)
  test("a non-string key doesn't raise", okN2)
  local peer = a.getPeer(ADDR_B)
  test("neither produced a secret", peer and peer.sharedSecret == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
