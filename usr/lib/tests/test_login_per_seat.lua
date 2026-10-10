-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: each seat's login is its own                 ║
-- ║                                                                ║
-- ║  1. shell/login.lua kept the seat's display (and W, H) in      ║
-- ║     module-level upvalues that login.run set. The kernel runs  ║
-- ║     one login per seat, all through the ONE cached module, so  ║
-- ║     the second login.run overwrote the first: on a 2-seat boot ║
-- ║     both logins drew on whichever seat started last. The other ║
-- ║     seat looked dead -- its keys were read by its own login,   ║
-- ║     but the echo landed on the other screen.                   ║
-- ║  2. Every seat opens First Boot Setup on a fresh install. Once ║
-- ║     one seat set root's password, the others stayed in theirs  ║
-- ║     and refused every answer as "Current password is           ║
-- ║     incorrect", forever.                                       ║
-- ║  Both seen on the headless machine with two GPUs, screens and  ║
-- ║  keyboards (2026-10-10).                                       ║
-- ║                                                                ║
-- ║  Drives real login.run calls as coroutines -- the way the      ║
-- ║  kernel runs them -- against fake screens and a fake account.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_login_per_seat.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_login_per_seat.lua"
local base = here:gsub("[^/\\]*$", "")
local function readSrc(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("*a"); f:close(); return s end
  end
end

-- A clock the test moves, so login's sleeps and its once-a-second check
-- happen when the test says.
local clock = 0
package.loaded.computer = {
  uptime = function() return clock end,
  pullSignal = function() return nil end,
  beep = function() end,
}
local src = assert(readSrc("tos/shell/login.lua"), "tos/shell/login.lua")
local L = assert(load(src, "=login.lua"))()

-- Records what was written; any other display call is a no-op.
local function fakeScreen()
  local d = { writes = {} }
  local theme = setmetatable({}, { __index = function() return 0 end })
  d.getSize = function() return 80, 25 end
  d.getTheme = function() return theme end
  d.set = function(_, _, text) d.writes[#d.writes + 1] = tostring(text) end
  d.fit = function(s) return s end
  return setmetatable(d, { __index = function() return function() end end })
end
local function wrote(d, text)
  for _, w in ipairs(d.writes) do if w:find(text, 1, true) then return true end end
  return false
end
local function echoed(d, n)
  for _, w in ipairs(d.writes) do if w == string.rep("*", n) then return true end end
  return false
end

-- root on a fresh install: password "root", firstBoot set.
local function newAccount()
  local acct = { password = "root", firstBoot = true, n = 0, changes = 0,
                 promoted = {}, loggedOut = {} }
  acct.users = setmetatable({
    getUser = function(name)
      if name ~= "root" then return nil end
      return { firstBoot = acct.firstBoot }
    end,
    login = function(_, pw)
      if pw ~= acct.password then return nil, "Invalid credentials" end
      acct.n = acct.n + 1
      return "T" .. acct.n
    end,
    changePassword = function(_, _, old, new)
      if old ~= acct.password then return false, "Current password is incorrect" end
      acct.password, acct.firstBoot = new, false
      acct.changes = acct.changes + 1
      return true
    end,
    promoteAfterFirstBoot = function(tok) acct.promoted[tok] = true; return true end,
    logout = function(tok) acct.loggedOut[tok] = true; return true end,
    guestEnabled = function() return false end,
  }, { __index = function() return function() end end })
  return acct
end

-- One seat: its own login (as the kernel takes it), run to its first read.
local function seat(acct)
  local inst = L.new and L.new() or L
  local d = fakeScreen()
  local co = coroutine.create(function()
    return inst.run({ display = d, users = acct.users, event = {}, proc = {} })
  end)
  local ok, err = coroutine.resume(co)
  assert(ok, err)
  return d, co
end

local function resume(co, ...)
  if coroutine.status(co) ~= "suspended" then return end
  local ok, err = coroutine.resume(co, ...)
  assert(ok, err)
end
local function typeAt(co, text)
  for c in text:gmatch(".") do resume(co, "key_down", "kb", c:byte(), c == "\r" and 28 or 30) end
end
-- Idle scheduler ticks: time passes, nobody types.
local function idle(co, secs)
  for _ = 1, math.floor(secs / 0.25) do clock = clock + 0.25; resume(co) end
end

print("=== two seats, two screens ===")
print()

do
  local acct = newAccount()
  local d1, co1 = seat(acct)
  local d2, co2 = seat(acct)
  test("both seats are waiting at First Boot Setup",
    coroutine.status(co1) == "suspended" and coroutine.status(co2) == "suspended")

  -- Only what each burst of typing drew: "abc" also draws "*" and "**".
  d1.writes, d2.writes = {}, {}
  typeAt(co1, "abc")
  test("seat 1's keys echo on seat 1's screen", echoed(d1, 3))
  test("...and not on seat 2's", not echoed(d2, 3))

  d1.writes, d2.writes = {}, {}
  typeAt(co2, "xy")
  test("seat 2's keys echo on seat 2's screen", echoed(d2, 2))
  test("...and not on seat 1's", not echoed(d1, 2))

  test("login.new() builds a separate login each time",
    L.new ~= nil and L.new().run ~= L.new().run)

  local init = readSrc("tos/kernel/init.lua") or ""
  test("the kernel takes a login per seat",
    init:find("loginScreen.new and loginScreen.new() or loginScreen", 1, true) ~= nil
    and init:find("pcall(seatLogin.run", 1, true) ~= nil)
end

print()
print("=== the first seat to answer sets the password ===")
print()

do
  local acct = newAccount()
  local d1, co1 = seat(acct)          -- token T1
  local d2, co2 = seat(acct)          -- token T2, from the same default password
  typeAt(co1, "secret1\rsecret1\r")
  idle(co1, 3)                         -- "Password set! Starting TOS..."
  test("seat 1 set root's password", acct.password == "secret1" and acct.changes == 1)
  test("...and its session was promoted", acct.promoted.T1 == true)

  -- Seat 2 is still showing its box. Nobody touches it.
  d2.writes = {}
  idle(co2, 4)
  test("seat 2 notices on its own and says where the password was set",
    wrote(d2, "Set at another screen"))
  test("...then shows the ordinary login", wrote(d2, "Username"))
  test("seat 2's default-password token is ended", acct.loggedOut.T2 == true)
  test("...and was never promoted", acct.promoted.T2 == nil)
  test("seat 2 changed nothing", acct.changes == 1 and acct.password == "secret1")
end

do
  -- The headless machine's case: seat 2 answers its stale box.
  local acct = newAccount()
  local _, co1 = seat(acct)
  local d2, co2 = seat(acct)
  typeAt(co1, "secret1\rsecret1\r")
  idle(co1, 3)
  d2.writes = {}
  typeAt(co2, "other22\rother22\r")
  idle(co2, 3)
  test("an answer typed into the stale box is not refused as a wrong password",
    not wrote(d2, "Current password is incorrect"))
  test("...it leaves for the ordinary login instead",
    wrote(d2, "Set at another screen") and acct.password == "secret1")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
