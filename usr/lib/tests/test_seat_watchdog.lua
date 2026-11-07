-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a seat whose shell was killed logs in again  ║
-- ║                                                                ║
-- ║  On the headless machine `kill 2` (the shell's own PID) said   ║
-- ║  "Killed PID 2", and the seat froze on that screen for good:   ║
-- ║  the kernel brought a login back only after a clean exit, a    ║
-- ║  logout, or when EVERY process was gone, and the rc.d services ║
-- ║  keep that last one from happening. The local worker saw the   ║
-- ║  frozen `ps` and took the shell for respawned.                 ║
-- ║                                                                ║
-- ║  Lifts seatsWithoutLogin out of the kernel and runs it, and    ║
-- ║  checks how the main loop uses it.                             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_seat_watchdog.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local f = assert(io.open("tos/kernel/init.lua", "rb"))
-- CRLF folded to LF: a Windows checkout (core.autocrlf) has CRLF, and the
-- patterns below are written with \n.
local src = f:read("a"):gsub("\r\n", "\n"); f:close()

local body = src:match("(local function seatsWithoutLogin.-end)%s*%-%-%[%[/TEST%-EXTRACT%-SEATS%]%]")
test("seatsWithoutLogin can be lifted out of the kernel", body ~= nil)
local pick = body and assert(load(body .. "\nreturn seatsWithoutLogin", "=seats", "t"))()

if pick then
  local live = { [10] = true, [20] = true }
  local function alive(pid) return pid ~= nil and live[pid] == true end
  local function run(indices, shells, logins, tries)
    return table.concat(pick(indices, shells, logins, alive, tries or {}, 5), ",")
  end

  print("=== which seats need their login back ===")
  test("a seat with a live shell does not", run({ 1 }, { [1] = 10 }, {}) == "")
  test("a seat at its live login does not", run({ 1 }, {}, { [1] = 20 }) == "")
  test("a seat whose shell was killed does", run({ 1 }, { [1] = 99 }, { [1] = 98 }) == "1")
  test("a seat with neither ever recorded does", run({ 1 }, {}, {}) == "1")
  test("only the dead seats of several, holes in the indices and all",
    run({ 1, 3, 4 }, { [1] = 10, [3] = 99 }, { [4] = 20 }) == "3",
    run({ 1, 3, 4 }, { [1] = 10, [3] = 99 }, { [4] = 20 }))

  print("=== a login that keeps dying cannot spin ===")
  test("under the limit it is tried again", run({ 1 }, {}, {}, { [1] = 4 }) == "1")
  test("at the limit the seat is left alone", run({ 1 }, {}, {}, { [1] = 5 }) == "")
  local tries = { [1] = 5 }
  pick({ 1 }, { [1] = 10 }, {}, alive, tries, 5)
  test("a shell running there again resets the count", tries[1] == nil)
end

print("=== how the kernel loop uses it ===")
local loop = src:match("while running do(.-)\n    end\n") or ""
local watch = loop:find("seatsWithoutLogin(", 1, true)
local tick = loop:find("proc.tick(signal.n > 0", 1, true)
local exited = loop:find('signal[1] == "tos_shell_exited"', 1, true)
test("the loop runs the watchdog", watch ~= nil)
test("...after the shell-exited handler, so a clean exit is never mistaken",
  exited ~= nil and watch ~= nil and exited < watch)
test("...and before the tick that could end a shell", watch ~= nil and tick ~= nil and watch < tick)
test("...once a second, not on every 0.1 s wake",
  loop:find("nowSeat - lastSeatCheck >= 1", 1, true) ~= nil)
test("a killed process counts as dead before it is reaped",
  src:find("p.state ~= DEAD", 1, true) ~= nil)
local spawn = src:match("local function spawnLoginProcess(.-)\n  end\n") or ""
test("every login is recorded for its seat", spawn:find("loginPIDs[dIdx] = loginPid", 1, true) ~= nil)
test("the respawn logs the killed seat's session out first",
  loop:find("usersmod.logout(sessionTokens[dIdx])", watch or 1, true) ~= nil)
local unplug = loop:match("for _, dIdx in ipairs%(removed%) do(.-)\n        end\n") or ""
test("an unplugged seat's login is killed with it, not left waiting",
  unplug:find("proc.kill(loginPIDs[dIdx]", 1, true) ~= nil, #unplug)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
