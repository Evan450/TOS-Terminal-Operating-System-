-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: setForeground Target Ownership     ║
-- ║  (#SEC H13) proc.setForeground must refuse to point  ║
-- ║  a seat at a process the caller may not control —    ║
-- ║  otherwise the caller's input is delivered to another ║
-- ║  user's process (input injection / privilege esc).    ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_fg_ownership.lua
--      (or `run /usr/lib/tests/test_fg_ownership.lua` inside TOS)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- Minimal stubs so process.lua loads standalone. The scheduler's optional
-- debug.sethook budget and the kernel.event removeSource call are both
-- pcall-guarded inside process.lua, but provide a no-op event module so
-- proc.kill (if ever reached) doesn't error.
package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return 1e6 end,
}
package.loaded["kernel.event"] = {
  removeSource = function() end,
}
-- Make the per-resume wall-clock hook a no-op: with uptime() frozen at 0 the
-- budget never trips anyway, but drop debug entirely so the test is immune to
-- host Lua hook quirks.
debug = nil

local here = (arg and arg[0]) or "usr/lib/tests/test_fg_ownership.lua"
local base = here:gsub("[^/\\]*$", "")
local proc
for _, p in ipairs({ base .. "../../../tos/kernel/process.lua",
    "tos/kernel/process.lua", "TOS-Dev/tos/kernel/process.lua" }) do
  local chunk = loadfile(p); if chunk then proc = chunk(); break end
end
if not proc or not proc.setForeground then
  print("FAIL: could not load process.lua / setForeground missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== setForeground Target-Ownership Tests ===")
print()

-- Target processes owned by different principals, on different seats.
local pRoot  = proc.spawn("root-shell",  function() coroutine.yield() end,
  { principal = { user = "root",  tier = 3 }, display = 1, inherit = false })
local pGuest = proc.spawn("guest-shell", function() coroutine.yield() end,
  { principal = { user = "guest", tier = 0 }, display = 2, inherit = false })

-- Results captured from inside each acting process (so currentPID is set by
-- the scheduler during the resume, exactly as in production).
local R = {}

-- A guest process that tries to point ITS OWN seat (2) at root's process.
-- This is the exploit: the seat check passes (it owns seat 2), but the
-- target-ownership check must deny it.
proc.spawn("guest-attacker", function()
  R.guestAtRoot = { proc.setForeground(pRoot, 2) }
  -- A guest pointing its seat at its own process must still be allowed.
  R.guestAtSelf = { proc.setForeground(pGuest, 2) }
  coroutine.yield()
end, { principal = { user = "guest", tier = 0 }, display = 2, inherit = false })

-- A root process may foreground anyone's process (root bypasses ownership).
proc.spawn("root-actor", function()
  R.rootAtGuest = { proc.setForeground(pGuest, 1) }
  coroutine.yield()
end, { principal = { user = "root", tier = 3 }, display = 1, inherit = false })

-- One scheduler tick resumes the acting processes with currentPID bound.
proc.tick()

test("guest may NOT foreground root's process onto its seat",
  false, R.guestAtRoot and R.guestAtRoot[1])
test("guest gets a permission error",
  true, type(R.guestAtRoot and R.guestAtRoot[2]) == "string")
test("guest MAY foreground its own process",
  true, R.guestAtSelf and R.guestAtSelf[1])
test("root MAY foreground another user's process",
  true, R.rootAtGuest and R.rootAtGuest[1])

-- Kernel-initiated calls (currentPID nil — boot seat-spawn, taskSwitcher)
-- bypass the check, same as proc.kill/signal/goTSR.
local kok = proc.setForeground(pRoot, 3)
test("kernel-context call (no currentPID) is allowed", true, kok)

-- ── #REV-3 — the login→shell foreground handoff ──────────────
-- Production flow: the seat's login broker (tier-0 "_login_" principal,
-- #135) spawns the shell as the AUTHENTICATED user and hands it the
-- seat's foreground. The H13 gate must allow this own-child-same-seat
-- handoff (it silently denied it, leaving the seat's input pointed at
-- the dead login process: shell drew, nothing typed ever arrived).
proc.spawn("login@4", function()
  -- Spawn "the shell" exactly as spawnShellForSeat does: explicit
  -- higher-tier principal, same display.
  local shellPid = proc.spawn("shell:root@4", function() coroutine.yield() end,
    { principal = { user = "root", tier = 3 }, display = 4, inherit = false })
  R.handoff = { proc.setForeground(shellPid, 4) }
  -- Same child, WRONG seat: still denied (the narrow exception is
  -- same-display only).
  R.handoffWrongSeat = { proc.setForeground(shellPid, 5) }
  -- Non-child on the same seat: still denied (H13's actual exploit).
  R.atStranger = { proc.setForeground(pRoot, 4) }
  coroutine.yield()
end, { principal = { user = "_login_", tier = 0, isLogin = true },
       display = 4, inherit = false })

proc.tick()

test("login may hand foreground to the shell it spawned (own child, own seat)",
  true, R.handoff and R.handoff[1])
test("own child on a DIFFERENT seat still denied",
  false, R.handoffWrongSeat and R.handoffWrongSeat[1])
test("wrong-seat denial is the seat check", true,
  type(R.handoffWrongSeat and R.handoffWrongSeat[2]) == "string")
test("non-child same-seat target still denied (H13 intact)",
  false, R.atStranger and R.atStranger[1])

-- ── {kernel=true} bypass (#REV multi-seat) ───────────────────
-- The System Monitor now runs AS a seat process (so it stops freezing
-- the box) but its switch action must stay god-mode, gated only by its
-- own canAct policy — so proc.setForeground grew an opts.kernel bypass
-- mirroring proc.kill({kernel=true}). SAFETY: this is trusted-caller-
-- only. The package sandbox hard-blocks require("kernel.*") (sandbox.lua
-- isKernelModule), so untrusted code can never reach `proc` to pass the
-- flag; every real caller is TOS-authored kernel/shell code, and only
-- the three kernel-loop sites pass it. The flag unconditionally sets
-- foreground regardless of caller identity — assert that contract with
-- a FRESH target so we don't disturb the shared fixtures above.
local pFresh = proc.spawn("fresh-root", function() coroutine.yield() end,
  { principal = { user = "root", tier = 3 }, display = 1, inherit = false })
local bypassResult
proc.spawn("guest-with-flag", function()
  -- The guest-exploit shape, but WITH the flag: it succeeds precisely
  -- because the flag is a trusted bypass (see safety note above).
  bypassResult = { proc.setForeground(pFresh, 2, { kernel = true }) }
  coroutine.yield()
end, { principal = { user = "guest", tier = 0 }, display = 2, inherit = false })
proc.tick()
test("opts.kernel bypasses the ownership check (trusted-caller contract)",
  true, bypassResult and bypassResult[1])
-- ...and WITHOUT the flag the same guest→root call is still denied.
local pFresh2 = proc.spawn("fresh-root-2", function() coroutine.yield() end,
  { principal = { user = "root", tier = 3 }, display = 1, inherit = false })
local noFlag
proc.spawn("guest-no-flag", function()
  noFlag = { proc.setForeground(pFresh2, 2) }
  coroutine.yield()
end, { principal = { user = "guest", tier = 0 }, display = 2, inherit = false })
proc.tick()
test("same call WITHOUT the flag is still denied (bypass is opt-in)",
  false, noFlag and noFlag[1])

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
