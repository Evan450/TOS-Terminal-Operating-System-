-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Seat Session Binding (CR-9)        ║
-- ║  helpers.sessionOf / helpers.canAccess must resolve   ║
-- ║  the SEAT-bound token, not the global currentSession. ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_seat_session_binding.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.loaded["computer"] = { uptime = function() return 0 end }

local here = (arg and arg[0]) or "usr/lib/tests/test_seat_session_binding.lua"
local base = here:gsub("[^/\\]*$", "")
local helpers
for _, p in ipairs({ base .. "../../../tos/shell/panels/helpers.lua",
    "tos/shell/panels/helpers.lua", "TOS-Dev/tos/shell/panels/helpers.lua" }) do
  local chunk = loadfile(p)
  if chunk then helpers = chunk(); break end
end
if not helpers then
  print("FAIL: could not load helpers.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Two distinct principals: the seat's own session (resolved from its
-- token) and a DIFFERENT session that the global currentSession() points
-- at (simulating another seat / stale global under setCurrent=false).
local seatSess   = { user = "alice", tier = 1 }   -- USER
local globalSess = { user = "root",  tier = 3 }   -- ROOT (wrong principal)

local function makeU(opts)
  opts = opts or {}
  return {
    getSession = function(tok)
      if tok == "alice-token" then return seatSess end
      return nil
    end,
    currentSession = function() return opts.current end,
    canAccessAs = function(sess, path, mode)
      -- Record which principal was used, and apply a trivial policy:
      -- ROOT may write anywhere; USER may not write /etc.
      makeU_lastSess = sess
      if not sess then return false, "no session" end
      if mode == "w" and sess.tier < 2 and path:sub(1, 4) == "/etc" then
        return false, "admin required"
      end
      return true
    end,
    canAccess = function() error("canAccess(global) must NOT be used when a seat token exists") end,
  }
end

local T = { error = 0 }

print("=== Seat Session Binding Tests ===")
print()

-- sessionOf prefers the seat token over the global.
local S1 = { U = makeU({ current = globalSess }), st = "alice-token", T = T }
test("sessionOf prefers seat token", seatSess, helpers.sessionOf(S1))

-- With no seat token, falls back to currentSession.
local S2 = { U = makeU({ current = globalSess }), st = nil, T = T }
test("sessionOf falls back to currentSession", globalSess, helpers.sessionOf(S2))

-- canAccess must evaluate against the SEAT principal (alice/USER), so a
-- write to /etc is DENIED — even though the global session is root.
makeU_lastSess = nil
local okWrite = helpers.canAccess(S1, "/etc/users.dat", "w")
test("write /etc denied for seat USER (not global root)", false, okWrite)
test("canAccessAs received the seat session", seatSess, makeU_lastSess)

-- The same seat user CAN read its own home.
test("seat USER may read /home/alice", true,
  helpers.canAccess(S1, "/home/alice/file", "r"))

-- Non-/etc write allowed for USER.
test("seat USER may write /home/alice", true,
  helpers.canAccess(S1, "/home/alice/x", "w"))

-- ── M-7: privilege gates read the LIVE tier, not cached S.userTier ──
-- S1's seat is alice (USER, tier 1); a stale cached userTier of 3 must
-- NOT grant admin/root.
S1.userTier = 3
test("liveTier uses session not cached userTier", 1, helpers.liveTier(S1))
test("adminOnly denies live USER despite cached root", false, helpers.adminOnly(S1))
test("rootOnly denies live USER despite cached root", false, helpers.rootOnly(S1))

-- A live ADMIN session passes adminOnly.
local adminU = {
  getSession = function(tok) if tok == "admin-token" then return { user = "carol", tier = 2 } end end,
  currentSession = function() return nil end,
  canAccessAs = function() return true end,
}
local Sadmin = { U = adminU, st = "admin-token", T = T, userTier = 0 }
test("adminOnly allows live ADMIN", true, helpers.adminOnly(Sadmin))
test("rootOnly denies live ADMIN", false, helpers.rootOnly(Sadmin))

-- Token present but session expired/revoked: fail closed to GUEST(0).
local expiredU = {
  getSession = function() return nil end,           -- expired
  currentSession = function() return { tier = 3 } end,  -- must NOT be used when token present
  canAccessAs = function() return true end,
}
local Sexp = { U = expiredU, st = "dead-token", T = T, userTier = 3 }
test("liveTier fails closed on expired session", 0, helpers.liveTier(Sexp))
test("adminOnly denies expired session", false, helpers.adminOnly(Sexp))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
