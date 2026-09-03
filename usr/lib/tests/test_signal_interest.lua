-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: signal-type interests (#REV finding #9)  ║
-- ║                                                            ║
-- ║  Every broadcast signal used to resume EVERY live process  ║
-- ║  (a modem flood = one resume per process per packet). A    ║
-- ║  process may now declare interests at spawn (or via        ║
-- ║  proc.setSignalInterest on itself): non-input broadcast    ║
-- ║  types outside the set skip its resume entirely. Directed  ║
-- ║  (queued) signals, input ticks, and timeout (nil) ticks    ║
-- ║  always wake it; no declaration = old behavior.            ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_signal_interest.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function eq(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1e6 end }
package.loaded["kernel.event"] = { removeSource = function() end }

local here = (arg and arg[0]) or "usr/lib/tests/test_signal_interest.lua"
local base = here:gsub("[^/\\]*$", "")
local proc
for _, p in ipairs({ base .. "../../../tos/kernel/process.lua",
    "tos/kernel/process.lua", "TOS-Dev/tos/kernel/process.lua" }) do
  local chunk = loadfile(p); if chunk then proc = chunk(); break end
end
if not proc or not proc.spawn then
  print("FAIL: could not load process.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== signal-interest Tests ===")
print()

-- A counting process: bumps its wake counter (and remembers the last
-- delivered signal) every time the scheduler resumes it.
local wakes, lastSig = {}, {}
local function counter(key)
  return function(...)
    while true do
      wakes[key] = (wakes[key] or 0) + 1
      local s = select(1, ...)
      if s ~= nil then lastSig[key] = s end
      s = coroutine.yield()
      if s ~= nil then lastSig[key] = s end
    end
  end
end
-- First resume runs the body up to the first yield — normalize by
-- ticking once (nil) after spawning, then zeroing the counters.
local pidAll  = proc.spawn("all",  counter("all"))
local pidMail = proc.spawn("mail", counter("mail"),
  { signalInterest = { "tos_mail" } })
local pidSet  = proc.spawn("setform", counter("setform"),
  { signalInterest = { modem_message = true } })
proc.tick(nil)
wakes = {}

local function tickWith(...)
  proc.tick(table.pack(...))
end

-- ── Broadcast filtering ────────────────────────────────────────────
tickWith("modem_message", "addr", "from", 1, 0, "payload")
eq("undeclared process wakes on modem_message", 1, wakes.all or 0)
eq("mail-only process NOT woken by modem_message", 0, wakes.mail or 0)
eq("set-form declaration works (modem interest wakes)", 1, wakes.setform or 0)
eq("undeclared process received the signal", "modem_message", lastSig.all)

wakes = {}
tickWith("tos_mail", "envelope")
eq("mail-only process wakes on its declared type", 1, wakes.mail or 0)
eq("undeclared process also wakes (default = everything)", 1, wakes.all or 0)
eq("modem-only process NOT woken by tos_mail", 0, wakes.setform or 0)

-- ── Timeout (nil) ticks always wake everyone ───────────────────────
wakes = {}
proc.tick(nil)
eq("nil tick wakes declared process", 1, wakes.mail or 0)
eq("nil tick wakes undeclared process", 1, wakes.all or 0)

-- ── Input ticks are exempt from filtering ──────────────────────────
wakes = {}
tickWith("key_down", "kb", 65, 30)
eq("input tick still wakes a declared process (background nil resume)",
  1, wakes.mail or 0)

-- ── Directed signals always deliver ────────────────────────────────
wakes = {}
proc.signalKernel(pidMail, "tos_custom", 42)
tickWith("modem_message", "addr", "from", 1, 0, "flood")
eq("queued directed signal beats the interest filter", 1, wakes.mail or 0)
eq("...and the directed signal is what got delivered", "tos_custom", lastSig.mail)

-- ── Self-service runtime declaration ───────────────────────────────
-- A process narrows its own interests mid-life via proc.setSignalInterest.
local narrowed = nil
local pidSelf = proc.spawn("self", function()
  narrowed = proc.setSignalInterest({ "tos_only_this" })
  while true do
    wakes.self = (wakes.self or 0) + 1
    coroutine.yield()
  end
end)
proc.tick(nil)   -- first resume: runs up to first yield (declares inside)
eq("setSignalInterest from inside the process succeeds", true, narrowed)
wakes = {}
tickWith("modem_message", "addr", "from", 1, 0, "x")
eq("runtime-narrowed process skips uninterested broadcast", 0, wakes.self or 0)
tickWith("tos_only_this")
eq("runtime-narrowed process wakes on its type", 1, wakes.self or 0)

-- setSignalInterest(nil) clears back to wake-on-everything.
local pidClear = proc.spawn("clear", function()
  proc.setSignalInterest({ "tos_never" })
  proc.setSignalInterest(nil)
  while true do
    wakes.clear = (wakes.clear or 0) + 1
    coroutine.yield()
  end
end)
proc.tick(nil)
wakes = {}
tickWith("modem_message", "addr", "from", 1, 0, "x")
eq("cleared declaration restores wake-on-all", 1, wakes.clear or 0)

-- Calling it with no current process fails closed.
local okOutside = proc.setSignalInterest({ "x" })
eq("setSignalInterest outside a process fails closed", false, okOutside)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
