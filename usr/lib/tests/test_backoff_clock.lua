-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the guessing brakes run on REAL seconds      ║
-- ║                                                                ║
-- ║  After three wrong passwords, login (#SEC H-5) and sudo's      ║
-- ║  elevation make the next attempt wait 5 s, doubling to 300 s.  ║
-- ║  Both measured the wait with os.time() -- and on OpenComputers ║
-- ║  os.time() is the IN-GAME clock: a game day is 86,400 of its   ║
-- ║  seconds and lasts 20 real minutes, so 72 go by every real     ║
-- ║  second. The 5 s wait lasted 0.07 s and the 300 s cap about    ║
-- ║  four. A wrong guess costs a password KDF, which takes longer  ║
-- ║  than that, so on a real machine neither ever refused anyone.  ║
-- ║  Seen on the headless OpenComputers machine: the fourth sudo   ║
-- ║  attempt, a second after the third, was judged instead of      ║
-- ║  told to wait, while the panel clock ran 7 game minutes in a   ║
-- ║  few real seconds.                                             ║
-- ║                                                                ║
-- ║  This drives the real kernel/users.lua under a clock shaped    ║
-- ║  like OpenComputers': os.time() at 72x, computer.uptime() at   ║
-- ║  real speed and starting again at every boot.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_backoff_clock.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

-- ── An OpenComputers-shaped clock ────────────────────────────────
local real = 1000          -- real seconds since the world started
local bootAt = real        -- when this boot began
local function advance(s) real = real + s end
local function reboot()
  bootAt = real
  _G._TOS.bootCount = (_G._TOS.bootCount or 0) + 1
end
_G._TOS = { bootCount = 7 }
package.loaded["computer"] = {
  uptime = function() return real - bootAt end,
  freeMemory = function() return 1e6 end,
}
local realOsTime = os.time
os.time = function(t)
  if t then return realOsTime(t) end
  return math.floor(real * 72) + 5000 * 3.6   -- game seconds, as OC reports them
end

package.loaded["component"] = { list = function() return function() end end }
package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

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
local principal = nil
package.loaded["kernel.process"] = {
  currentSession = function() return principal end,
  currentToken = function() return nil end,
}

local users = require("kernel.users")
users.init({ fs = fs, crypto = package.loaded["kernel.crypto"], log = nil })
local T = users.TIER
local rootS = { user = "root", tier = T.ROOT }
principal = rootS
assert(users.create("root", "bob", "bobpass1", T.USER))
assert(users.create("root", "erin", "erinpass1", T.USER))
assert(users.setElevation(rootS, "letmein9", T.ROOT))
principal = nil
local erinS = { user = "erin", tier = T.USER, home = "/home/erin" }

print("=== the guessing brakes run on real seconds ===")

print("-- sudo --")
for i = 1, 3 do
  advance(1)
  users.elevate(erinS, "guess" .. i)
end
advance(1)                                   -- one REAL second later
local e4, why4 = users.elevate(erinS, "letmein9")
test("a 4th attempt one real second later must wait, right password or not",
  e4 == nil and type(why4) == "string" and why4:find("try again in", 1, true) ~= nil, why4)
test("...and it is told the real wait: 4s left of 5",
  type(why4) == "string" and why4:find("try again in 4s", 1, true) ~= nil, why4)

reboot(); advance(2)
users.init({ fs = fs, crypto = package.loaded["kernel.crypto"], log = nil })
local e5 = users.elevate(erinS, "letmein9")
test("a reboot does not cut the wait short: only this boot's 2 s count", e5 == nil)
advance(4)
test("once 5 real seconds have passed in this boot, the right password elevates",
  users.elevate(erinS, "letmein9") ~= nil)

print("-- login --")
for i = 1, 3 do
  advance(1)
  users.login("bob", "wrong" .. i, { setCurrent = false })
end
advance(1)
local tok = users.login("bob", "bobpass1", { setCurrent = false })
test("a 4th login one real second later is refused, even with the right password", tok == nil)
advance(5)
tok = users.login("bob", "bobpass1", { setCurrent = false })
test("after the real 5 s it succeeds", tok ~= nil)

print("-- after an upgrade: a stamp the old code wrote --")
do
  -- An older build stamped failures with a bare os.time() number. Plant
  -- one, three failures deep, as if TOS had just been upgraded and booted.
  local S = require("kernel.serialize")
  local db = S.decode(store["/etc/users.dat"])
  db.bob.failedAttempts = 3
  db.bob.lastFailedAt = os.time() - 100000
  store["/etc/users.dat"] = S.encode(db)
  reboot(); advance(1)
  users.init({ fs = fs, crypto = package.loaded["kernel.crypto"], log = nil })
  test("an old-style stamp still makes the next login wait",
    users.login("bob", "bobpass1", { setCurrent = false }) == nil)
  advance(5)
  test("...for the real 5 s, counted from this boot",
    users.login("bob", "bobpass1", { setCurrent = false }) ~= nil)
end

os.time = realOsTime
print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
