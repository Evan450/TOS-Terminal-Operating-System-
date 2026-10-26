-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a reinstalled peer's new key is noticed      ║
-- ║                                                                ║
-- ║  Two TRUSTED peers derive their secret by Diffie-Hellman. A    ║
-- ║  machine that is reinstalled keeps its address (the network    ║
-- ║  card) but makes a new X25519 identity. It derived a fresh     ║
-- ║  secret; its peers kept the old one, because tryAutoSecret     ║
-- ║  never replaces a secret and noteDhPublicKey overwrote dhPub   ║
-- ║  without a word. Every sealed packet then failed and nothing   ║
-- ║  said why. Accepting the new key by itself would let anything  ║
-- ║  that can send a HELLO as that address swap in its own key, so ║
-- ║  the change is flagged and logged, and `net trust rekey`       ║
-- ║  (trust.rekey, admin) is the operator's way to accept it.      ║
-- ║  Same two-instance technique as test_trust_dh.lua.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_trust_rekey.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }

local function freshTrust() return assert(loadfile("tos/kernel/net/trust.lua"))() end
local function fsStub()
  local files = {}
  return {
    exists = function(p) return files[p] ~= nil end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, d) files[p] = d; return true end,
    writeFileAtomic = function(p, d) files[p] = d; return true end,
  }, files
end
local function fakeCrypto(letter) return { salt = function(n) return string.rep(letter, n) end } end
local function logStub()
  local warns = {}
  return { info = function() end, warn = function(_, m) warns[#warns + 1] = m end }, warns
end

local ROOT, ADMIN, USER = "root", 2, 1
local A = "aaaaaaaa-1111-1111-1111-111111111111"
local B = "bbbbbbbb-2222-2222-2222-222222222222"

-- A and B trust each other and agree on a DH secret. Returns A's side,
-- A's fs and log, and B.
local function pairUp()
  local fsA = fsStub()
  local logA, warns = logStub()
  local a = freshTrust(); a.init({ fs = fsA, crypto = fakeCrypto("A"), log = logA })
  local b = freshTrust(); b.init({ fs = (fsStub()), crypto = fakeCrypto("B") })
  a.setLevel(ROOT, B, 2, ADMIN); b.setLevel(ROOT, A, 2, ADMIN)
  a.noteDhPublicKey(B, b.getMyDhPublicKey()); b.noteDhPublicKey(A, a.getMyDhPublicKey())
  return a, fsA, warns, b
end

-- B is reinstalled: same address, an empty /etc, a new identity, and its
-- operator trusts A again. Both then hear each other's HELLO.
local function reinstallB(a, letter)
  local b2 = freshTrust(); b2.init({ fs = (fsStub()), crypto = fakeCrypto(letter or "C") })
  b2.setLevel(ROOT, A, 2, ADMIN)
  b2.noteDhPublicKey(A, a.getMyDhPublicKey())
  a.noteDhPublicKey(B, b2.getMyDhPublicKey())
  return b2
end

local function secretOf(t, addr) return (t.getPeer(addr) or {}).sharedSecret end
local function listed(t, addr)
  for _, p in ipairs(t.listPeers()) do if p.address == addr then return p end end
end

print("=== A reinstalled peer's new key is noticed, not trusted ===")
print()

do
  local a, _, warns, b = pairUp()
  local old = secretOf(a, B)
  test("first contact: both sides derive the same secret", old ~= nil and old == secretOf(b, A))
  test("...and nothing is flagged", not (a.getPeer(B)).dhKeyChanged)

  local b2 = reinstallB(a)
  test("the reinstalled side derives a new secret", secretOf(b2, A) ~= nil and secretOf(b2, A) ~= old)
  test("the new key is NOT accepted by itself: A keeps its secret", secretOf(a, B) == old)
  test("the peer is flagged as having a new key", (a.getPeer(B)).dhKeyChanged == true)
  test("listPeers says so", (listed(a, B) or {}).keyChanged == true)
  test("one warning is logged", #warns == 1)
  test("...naming the command that fixes it", (warns[1] or ""):find("net trust rekey", 1, true) ~= nil)
  test("...and that the secret came from the old key",
    (warns[1] or ""):find("old key", 1, true) ~= nil)
  a.noteDhPublicKey(B, b2.getMyDhPublicKey())
  test("the next HELLO with the same new key does not warn again", #warns == 1)

  local ok, err = a.rekey("alice", B, USER)
  test("rekey below admin is refused", ok == false and tostring(err):find("Admin", 1, true) ~= nil)
  test("...and changes nothing", secretOf(a, B) == old)

  ok, err = a.rekey(ROOT, B, ADMIN)
  test("rekey as admin succeeds (" .. tostring(err) .. ")", ok == true)
  test("the two sides agree again", secretOf(a, B) == secretOf(b2, A))
  test("the flag is cleared", not (a.getPeer(B)).dhKeyChanged)
  test("listPeers no longer marks it", (listed(a, B) or {}).keyChanged == false)
end

do
  local a, fsA, warns, b = pairUp()
  local old = secretOf(a, B)
  local oldKey = b.getMyDhPublicKey()
  reinstallB(a)
  a.noteDhPublicKey(B, oldKey)
  test("a key that changes back to the secret's own key clears the flag",
    not (a.getPeer(B)).dhKeyChanged and secretOf(a, B) == old)

  -- Survives a reboot: the flag and where the secret came from persist.
  reinstallB(a, "D")
  local a2 = freshTrust(); a2.init({ fs = fsA, crypto = fakeCrypto("A") })
  test("the flag survives a reload", (a2.getPeer(B)).dhKeyChanged == true)
  test("...and so does the key the secret came from", (a2.getPeer(B)).secretDhPub == oldKey)
  local _ = warns
end

do
  -- Someone who can send a HELLO as B offers their own key. That is the
  -- same event as a reinstall from A's side, and must not reach the secret.
  local a, _, warns = pairUp()
  local old = secretOf(a, B)
  a.noteDhPublicKey(B, string.rep("\7", 32))
  test("a forged HELLO's key does not replace the secret", secretOf(a, B) == old)
  test("...it is flagged like any other change", (a.getPeer(B)).dhKeyChanged == true and #warns == 1)
end

do
  -- A secret set by hand did not come from any key.
  local logA, warns = logStub()
  local a = freshTrust(); a.init({ fs = (fsStub()), crypto = fakeCrypto("A"), log = logA })
  a.setLevel(ROOT, B, 2, ADMIN)
  a.setSecret(ROOT, B, string.rep("s", 32), ADMIN)
  a.noteDhPublicKey(B, string.rep("\1", 32))
  test("a hand-set secret is kept when the first key arrives", secretOf(a, B) == string.rep("s", 32))
  test("...and that is not a change of key", not (a.getPeer(B)).dhKeyChanged)
  a.noteDhPublicKey(B, string.rep("\2", 32))
  test("a later key change on a hand-set secret is flagged", (a.getPeer(B)).dhKeyChanged == true)
  test("...with wording for a hand-set secret", (warns[1] or ""):find("set by hand", 1, true) ~= nil)
  test("setSecret clears the flag (the operator re-paired)",
    a.setSecret(ROOT, B, string.rep("t", 32), ADMIN) and not (a.getPeer(B)).dhKeyChanged)
end

do
  local a = freshTrust(); a.init({ fs = (fsStub()), crypto = fakeCrypto("A") })
  a.setLevel(ROOT, B, 1, ADMIN)
  a.noteDhPublicKey(B, string.rep("\3", 32))
  local ok, err = a.rekey(ROOT, B, ADMIN)
  test("rekey refuses a peer that is not TRUSTED", ok == false and tostring(err):find("TRUSTED", 1, true) ~= nil)
  local c = "cccccccc-3333-3333-3333-333333333333"
  a.setLevel(ROOT, c, 2, ADMIN)
  ok, err = a.rekey(ROOT, c, ADMIN)
  test("rekey refuses a peer that has sent no key", ok == false and tostring(err):find("hello", 1, true) ~= nil)
  ok = a.rekey(ROOT, "dddddddd", ADMIN)
  test("rekey refuses an unknown peer", ok == false)
end

do
  -- The shell offers it, and the man page names it.
  local h = io.open("tos/shell/ext.lua", "rb"); local ext = h:read("a"); h:close()
  test("`net trust rekey` is a shell subcommand", ext:find('sub2 == "rekey"', 1, true) ~= nil)
  h = io.open("usr/man/net.man", "rb"); local man = h:read("a"); h:close()
  test("net.man documents it", man:find("trust rekey", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
