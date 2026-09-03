-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: privilege elevation (sudo core)         ║
-- ║                                                            ║
-- ║  A separate elevation password lets a non-root USER do     ║
-- ║  higher-tier ACTIONS temporarily, capped at a root-set     ║
-- ║  ceiling, without touching the root account. Pins:         ║
-- ║  root-only config, opt-in (unset by default), guest        ║
-- ║  refusal, wrong-password refusal, cap clamping, and that   ║
-- ║  the elevated session is a NEW session bound to the same   ║
-- ║  user (never root).                                        ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_elevation.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end }
package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- Deterministic crypto stub: hash = "H:"..salt.."|"..pw ; verify compares.
package.loaded["kernel.crypto"] = {
  init = function() end,
  salt = function() return "SALT" end,
  hashPassword = function(pw, salt) return "H:" .. tostring(salt) .. "|" .. tostring(pw) end,
  verifyPassword = function(pw, salt, hash)
    return hash == "H:" .. tostring(salt) .. "|" .. tostring(pw), false
  end,
  token = (function() local n = 0; return function() n = n + 1; return "tok" .. n end end)(),
  hasHardware = function() return false end,
}
-- In-memory fs.
local store = {}
local fs = {
  exists = function(p) return store[p] ~= nil end,
  readFile = function(p) return store[p] end,
  writeFile = function(p, d) store[p] = d; return true end,
  writeFileAtomic = function(p, d) store[p] = d; return true end,
  remove = function(p) store[p] = nil; return true end,
  makeDirectory = function(p) store[p .. "/"] = ""; return true end,
  isDirectory = function(p) return store[p .. "/"] ~= nil end,
  list = function() return {} end,
}
package.loaded["kernel.serialize"] = require("kernel.serialize")

local users = require("kernel.users")
users.init({ fs = fs, crypto = package.loaded["kernel.crypto"], log = nil })
local T = users.TIER

print("=== privilege elevation Tests ===")
print()

-- Sessions we act as (the module accepts an explicit session arg).
local rootS  = { user = "root",  tier = T.ROOT }
local aliceS = { user = "alice", tier = T.USER, home = "/home/alice" }
local guestS = { user = "guest", tier = T.GUEST }

-- ── Opt-in: disabled until root configures it ──────────────────────
test("elevation disabled by default", users.elevationInfo().configured == false)
test("elevate refused when unconfigured", (users.elevate(aliceS, "anything")) == nil)

-- ── Only root may configure ────────────────────────────────────────
test("USER cannot set elevation", not (users.setElevation(aliceS, "letmein9", T.ROOT)))
test("guest cannot set elevation", not (users.setElevation(guestS, "letmein9", T.ROOT)))
test("bad cap rejected", not (users.setElevation(rootS, "letmein9", 99)))
test("root sets elevation (cap root)", (users.setElevation(rootS, "letmein9", T.ROOT)))
test("now configured", users.elevationInfo().configured)
eq("info reports the cap", T.ROOT, users.elevationInfo().cap)
test("info leaks no secret", users.elevationInfo().hash == nil
  and users.elevationInfo().salt == nil)

-- ── Elevation behavior ─────────────────────────────────────────────
test("wrong password refused", (users.elevate(aliceS, "nope")) == nil)
test("guest cannot elevate even with the password", (users.elevate(guestS, "letmein9")) == nil)
local elev = users.elevate(aliceS, "letmein9")
test("USER elevates with the correct password", elev ~= nil)
eq("elevated tier reaches the cap (root)", T.ROOT, elev and elev.tier)
eq("elevated session KEEPS the caller's identity (not root)", "alice", elev and elev.user)
test("elevated session is flagged", elev and elev.elevated == true)
eq("audit: raised-from tier recorded", T.USER, elev and elev.elevatedFrom)
test("elevated session is a DISTINCT table (not the login session)", elev ~= aliceS)
test("original session unchanged", aliceS.tier == T.USER)

-- ── Cap clamps below root ──────────────────────────────────────────
test("root re-caps elevation to ADMIN", (users.setElevation(rootS, "letmein9", T.ADMIN)))
local elevA = users.elevate(aliceS, "letmein9")
eq("elevation now capped at ADMIN", T.ADMIN, elevA and elevA.tier)
-- An ADMIN elevating with an ADMIN-cap stays ADMIN (never demoted, never over cap).
local adminS = { user = "bob", tier = T.ADMIN }
local elevB = users.elevate(adminS, "letmein9")
eq("ADMIN caller with ADMIN cap stays ADMIN", T.ADMIN, elevB and elevB.tier)

-- ── sudo -s: register an elevated token ────────────────────────────
local tok = users.registerSession(elevA)
test("registerSession returns a token", type(tok) == "string")
test("token resolves to the elevated session", users.getSession(tok) == elevA)

-- ── Elevated session authorizes account actions (the sudo path) ────
-- users.setTier/create authorize on the EFFECTIVE tier — the process-bound
-- session's tier (which sudo elevation raises), not the stored account tier.
-- Stub the process principal so users.currentSession() resolves what we set.
local procPrincipal = nil
package.loaded["kernel.process"] = {
  currentSession = function() return procPrincipal end,
  currentToken   = function() return nil end,
}
users.setElevation(rootS, "letmein9", T.ROOT)   -- re-enable, root cap
-- Real accounts to act on (created by root).
procPrincipal = rootS
test("root creates alice", (users.create("root", "alice", "alicepass1", T.USER)))
test("root creates carol", (users.create("root", "carol", "carolpass1", T.USER)))
local realAlice = { user = "alice", tier = T.USER }
-- A PLAIN user session cannot manage accounts...
procPrincipal = realAlice
test("non-elevated USER cannot setTier", not (users.setTier("alice", "carol", T.ADMIN)))
test("non-elevated USER cannot create", not (users.create("alice", "dave", "davepass1", T.USER)))
-- ...but once elevated (to ROOT), the SAME user can.
local elevAlice = users.elevate(realAlice, "letmein9")
eq("alice elevates to root", T.ROOT, elevAlice and elevAlice.tier)
procPrincipal = elevAlice
test("elevated USER can setTier (carol -> admin)", (users.setTier("alice", "carol", T.ADMIN)))
test("elevated USER can create an account", (users.create("alice", "dave", "davepass1", T.USER)))
test("elevated-to-root USER can grant ROOT", (users.setTier("alice", "dave", T.ROOT)))
-- Cap matters: elevated only to ADMIN cannot grant ROOT.
users.setElevation(rootS, "letmein9", T.ADMIN)
local elevAdmin = users.elevate(realAlice, "letmein9")
eq("alice now capped at admin", T.ADMIN, elevAdmin and elevAdmin.tier)
procPrincipal = elevAdmin
test("admin-capped elevation can setTier to admin", (users.setTier("alice", "carol", T.ADMIN)))
test("admin-capped elevation canNOT grant ROOT", not (users.setTier("alice", "carol", T.ROOT)))
procPrincipal = nil   -- restore for the disable section below

-- ── Disable ────────────────────────────────────────────────────────
test("USER cannot disable elevation", not (users.clearElevation(aliceS)))
test("root disables elevation", (users.clearElevation(rootS)))
test("disabled again", users.elevationInfo().configured == false)
test("elevate refused after disable", (users.elevate(aliceS, "letmein9")) == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
