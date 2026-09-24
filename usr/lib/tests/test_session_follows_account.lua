-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a live session follows its account            ║
-- ║                                                                ║
-- ║  A session is a copy of the account taken at login. The shell's ║
-- ║  tier gate (helpers.liveTier) and securefs both read that copy  ║
-- ║  -- the seat's shell process holds the very same table as its   ║
-- ║  principal -- and nothing ever wrote it again:                  ║
-- ║   * root demoted an admin; the admin's open session stayed      ║
-- ║     ADMIN until they logged out (never, with sessionTimeout=0). ║
-- ║   * root locked an account; its open session carried on.        ║
-- ║  And sudo was honoured by create/setTier only: an elevated user ║
-- ║  passed the shell's gate for userdel/usermod/passwd and was     ║
-- ║  then refused by the kernel, which re-read the STORED tier.     ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.users.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_session_follows_account.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end }

local CURRENT = nil
package.loaded["kernel.process"] = {
  currentSession = function() return CURRENT end,
  currentToken   = function() return nil end,
}
local crypto = {
  init = function() end,
  salt = function() return "SALT" end,
  hashPassword = function(pw, salt) return "H:" .. tostring(salt) .. "|" .. tostring(pw) end,
  verifyPassword = function(pw, salt, hash)
    return hash == "H:" .. tostring(salt) .. "|" .. tostring(pw), false
  end,
  token = (function() local n = 0; return function() n = n + 1; return "tok" .. n end end)(),
  hasHardware = function() return false end,
}
package.loaded["kernel.crypto"] = crypto

local store, refuse = {}, false
local function put(p, d)
  if refuse then return false, "not enough space" end
  store[p] = d; return true
end
local fs = {
  exists = function(p) return store[p] ~= nil end,
  readFile = function(p) return store[p] end,
  writeFile = put, writeFileAtomic = put,
  remove = function(p) store[p] = nil; return true end,
  makeDirectory = function(p) store[p .. "/"] = ""; return true end,
  isDirectory = function(p) return store[p .. "/"] ~= nil end,
  list = function() return {} end,
}

local users = require("kernel.users")
users.init({ fs = fs, crypto = crypto })
local T = users.TIER

-- Accounts, made as the kernel.
CURRENT = users.kernelSession()
assert(users.changePassword("root", "root", "root", "rootpw12"))
for _, spec in ipairs({
  { "adam", T.ADMIN }, { "amy", T.ADMIN }, { "bob", T.USER },
  { "carl", T.USER }, { "dora", T.USER }, { "eve", T.USER }, { "fay", T.USER },
}) do
  assert(users.create("root", spec[1], spec[1] .. "pw1234", spec[2]))
end
local rootS = users.sessionFor("root")

local function loginAs(name)
  CURRENT = nil
  return users.login(name, name .. "pw1234", { setCurrent = false })
end

print("=== a live session follows its account ===")
print()

print("-- demotion and promotion reach open sessions --")
do
  local tok = loginAs("adam")
  local live = users.getSession(tok)
  eq("adam's session starts at ADMIN", T.ADMIN, live and live.tier)
  CURRENT = rootS
  test("root demotes adam", (users.setTier("root", "adam", T.USER)))
  eq("...and adam's OPEN session is now USER", T.USER, users.getSession(tok).tier)
  eq("...realTier too", T.USER, users.getSession(tok).realTier)
  test("...it is the same table a shell process holds", users.getSession(tok) == live)

  local tokB = loginAs("bob")
  CURRENT = rootS
  test("root promotes bob", (users.setTier("root", "bob", T.ADMIN)))
  eq("...and bob's open session is ADMIN", T.ADMIN, users.getSession(tokB).tier)

  -- A refused save is no change at all.
  refuse = true
  test("a demotion that cannot be saved is refused", not users.setTier("root", "bob", T.USER))
  refuse = false
  eq("...and bob's session is untouched", T.ADMIN, users.getSession(tokB).tier)
end

print()
print("-- an elevated session is re-derived, not overwritten --")
do
  test("root configures elevation (cap ADMIN)", (users.setElevation(rootS, "elevpw99", T.ADMIN)))
  local tokC = loginAs("carl")
  local elev = users.elevate(users.getSession(tokC), "elevpw99")
  local etok = users.registerSession(elev)
  eq("carl's sudo -s session is ADMIN", T.ADMIN, users.getSession(etok).tier)
  CURRENT = rootS
  users.setTier("root", "carl", T.GUEST)
  eq("demoting carl to GUEST drops the elevated session to GUEST", T.GUEST, users.getSession(etok).tier)
  users.setTier("root", "carl", T.USER)
  eq("back to USER, the elevated session holds its cap again", T.ADMIN, users.getSession(etok).tier)
  eq("...and his plain session is USER", T.USER, users.getSession(tokC).tier)
end

print()
print("-- locking ends the sessions that are already open --")
do
  local tokD = loginAs("dora")
  local live = users.getSession(tokD)
  CURRENT = rootS
  test("root locks dora", (users.setLocked("root", "dora", true)))
  test("...her token no longer resolves", users.getSession(tokD) == nil)
  eq("...and the table a process may still hold is GUEST", T.GUEST, live.tier)
  test("...marked revoked", live.revoked == true)
  test("...and she cannot log back in", loginAs("dora") == nil)
  CURRENT = rootS
  test("unlocking works as before", (users.setLocked("root", "dora", false)))
  test("...and she can log in again", loginAs("dora") ~= nil)
  CURRENT = rootS
  local tokE = loginAs("eve")
  CURRENT = rootS
  test("a refused lock is refused", (function()
    refuse = true
    local ok = users.setLocked("root", "eve", true)
    refuse = false
    return not ok
  end)())
  test("...and eve's session survives it", users.getSession(tokE) ~= nil)
end

print()
print("-- deleting strips the principal a process may still hold --")
do
  local tokF = loginAs("fay")
  local live = users.getSession(tokF)
  CURRENT = rootS
  test("root deletes fay", (users.delete("root", "fay")))
  test("...her token no longer resolves", users.getSession(tokF) == nil)
  eq("...and the held table is GUEST", T.GUEST, live.tier)
end

print()
print("-- sudo counts for delete, lock and password resets --")
do
  CURRENT = rootS
  users.setElevation(rootS, "elevpw99", T.ROOT)
  assert(users.create("root", "gus", "guspw1234", T.USER))
  assert(users.create("root", "hal", "halpw1234", T.USER))
  local plain = { user = "eve", tier = T.USER }
  CURRENT = plain
  test("a plain USER cannot lock", not users.setLocked("eve", "gus", true))
  test("a plain USER cannot reset another's password",
    not users.changePassword("eve", "gus", nil, "newpw1234"))
  test("a plain USER cannot delete", not users.delete("eve", "hal"))
  local elev = users.elevate(plain, "elevpw99")
  eq("eve elevates to ROOT", T.ROOT, elev and elev.tier)
  CURRENT = elev
  test("elevated: lock", (users.setLocked("eve", "gus", true)))
  test("elevated: unlock", (users.setLocked("eve", "gus", false)))
  test("elevated: reset another's password",
    (users.changePassword("eve", "gus", nil, "newpw1234")))
  test("elevated: delete", (users.delete("eve", "hal")))
  -- Capped at ADMIN, the outranks rule still holds.
  CURRENT = rootS
  users.setElevation(rootS, "elevpw99", T.ADMIN)
  local capped = users.elevate(plain, "elevpw99")
  CURRENT = capped
  test("admin-capped elevation cannot reset root's password",
    not users.changePassword("eve", "root", nil, "takeover1"))
  test("admin-capped elevation cannot lock root", not users.setLocked("eve", "root", true))
end

print()
print("-- guest and first-boot sessions keep their own rules --")
do
  CURRENT = users.kernelSession()
  assert(users.create("root", "ivy", "ivypw1234", T.USER))
  -- A first-boot-style restricted session: stays GUEST until promotion.
  local restricted = { user = "ivy", tier = T.GUEST, realTier = T.USER,
    passwordChangeOnly = true, lastActivity = 0 }
  local rtok = users.registerSession(restricted)
  CURRENT = rootS
  users.setTier("root", "ivy", T.ADMIN)
  eq("a restricted session stays GUEST", T.GUEST, users.getSession(rtok).tier)
  eq("...but will promote to the NEW tier", T.ADMIN, users.getSession(rtok).realTier)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
