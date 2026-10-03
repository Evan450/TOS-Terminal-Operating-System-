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

-- ── #SEC: elevation guesses are throttled like logins (H-5) ─────────
-- With cap = root the elevation password IS a root password, any USER
-- may try it, and every wrong guess used to be answered at once. It now
-- takes login's curve, counted per ACCOUNT in the user DB so that a
-- reboot (which a lone USER may do) does not reset it.
print()
print("-- elevation backoff --")
do
  -- The wait runs on computer.uptime(), in real seconds; os.time() is the
  -- in-game clock on OpenComputers (test_backoff_clock.lua says why), so
  -- this moves uptime.
  local C = package.loaded["computer"]
  local realUptime = C.uptime
  local now = 100
  C.uptime = function() return now end
  users.setElevation(rootS, "letmein9", T.ROOT)
  procPrincipal = rootS
  test("root creates erin", (users.create("root", "erin", "erinpass1", T.USER)))
  procPrincipal = nil
  local erinS = { user = "erin", tier = T.USER, home = "/home/erin" }

  for i = 1, 3 do
    local e, why = users.elevate(erinS, "guess" .. i)
    test("wrong guess " .. i .. " is simply refused",
      e == nil and why == "Incorrect elevation password")
  end
  local e4, why4 = users.elevate(erinS, "letmein9")
  test("a 4th attempt at once is throttled -- even with the RIGHT password", e4 == nil)
  test("...and says so", type(why4) == "string" and why4:find("try again in 5s", 1, true) ~= nil)

  -- A reboot re-reads the user DB; the count lives there.
  users.init({ fs = fs, crypto = package.loaded["kernel.crypto"], log = nil })
  test("the cooldown survives a reboot", (users.elevate(erinS, "letmein9")) == nil)

  now = now + 6
  local e5, why5 = users.elevate(erinS, "wrong-again")
  test("once it passes, a wrong guess is judged again",
    e5 == nil and why5 == "Incorrect elevation password")
  local _, why6 = users.elevate(erinS, "letmein9")
  test("...and the next cooldown is longer (10s)",
    type(why6) == "string" and why6:find("try again in 10s", 1, true) ~= nil)

  now = now + 11
  local ok7 = users.elevate(erinS, "letmein9")
  test("after the cooldown the right password elevates", ok7 ~= nil)
  local rec = users.getUser("erin")
  test("...and success clears the count", rec and rec.elevFailed == nil and rec.elevFailedAt == nil)
  test("another account was never throttled by erin's guesses",
    users.elevate({ user = "carol", tier = T.ADMIN }, "letmein9") ~= nil)
  C.uptime = realUptime
end

-- ── Disable ────────────────────────────────────────────────────────
test("USER cannot disable elevation", not (users.clearElevation(aliceS)))
test("root disables elevation", (users.clearElevation(rootS)))
test("disabled again", users.elevationInfo().configured == false)
test("elevate refused after disable", (users.elevate(aliceS, "letmein9")) == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
