-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: compat.event listen / ignore identity       ║
-- ║                                                                ║
-- ║  OpenOS identifies a listener by the PAIR (signal name,        ║
-- ║  callback) — lib/core/full_event.lua matches                   ║
-- ║    handler.key == name and handler.callback == callback        ║
-- ║  in listen (to reject a duplicate) and in ignore (to find the  ║
-- ║  one to remove).                                               ║
-- ║                                                                ║
-- ║  TOS's shim tracked callbacks in a map keyed on the FUNCTION   ║
-- ║  alone, one signal deep, and that breaks the ordinary case of  ║
-- ║  one handler serving several signals — which is most of the    ║
-- ║  reason a program writes a shared handler in the first place   ║
-- ║  (touch+drag, key_down+key_up, component_added+removed):       ║
-- ║                                                                ║
-- ║    listen("touch", f)  then  listen("drag", f)                 ║
-- ║      — the second saw f already present and returned false     ║
-- ║        without registering. `drag` silently never fired.       ║
-- ║    ignore("touch", f)                                          ║
-- ║      — removed whatever single signal f happened to be mapped  ║
-- ║        to, which could be a different one entirely.            ║
-- ║                                                                ║
-- ║  Both failures are quiet: nothing errors, a callback just      ║
-- ║  stops being called (or keeps being called).                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_event.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_compat_event.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

package.loaded["computer"] = { uptime = function() return 0 end,
  pullSignal = function() return nil end }

-- A stand-in kernel.event that records registrations, so the test can see
-- exactly what the shim asked the kernel for rather than inferring it.
local kernelLog = {}
local nextId = 0
local live = {}          -- id -> { signal, callback }
package.loaded["kernel.event"] = {
  on = function(signal, callback, source)
    nextId = nextId + 1
    live[nextId] = { signal = signal, callback = callback }
    kernelLog[#kernelLog + 1] = { "on", signal, nextId }
    return nextId
  end,
  off = function(signal, id)
    kernelLog[#kernelLog + 1] = { "off", signal, id }
    if live[id] and live[id].signal == signal then live[id] = nil; return true end
    return false
  end,
  once = function() end,
  push = function() end,
  pull = function() return nil end,
  pullFiltered = function() return nil end,
  interval = function() return 0 end,
  cancelTimer = function() return true end,
}

local event = require("compat.event")

print("=== compat.event listen/ignore Tests ===")
print()

local function f() end
local function g() end

-- ── One callback, several signals ──────────────────────────────────
print("-- one handler, several signals --")
eq("listen(touch, f) registers", true, event.listen("touch", f))
eq("listen(drag, f) ALSO registers", true, event.listen("drag", f))
eq("listen(drop, f) too", true, event.listen("drop", f))

do
  local signals = {}
  for _, rec in pairs(live) do
    if rec.callback == f then signals[rec.signal] = true end
  end
  test("the kernel really holds all three", signals.touch and signals.drag and signals.drop)
end

-- ── Duplicate is a no-op only for the SAME signal ──────────────────
print()
print("-- duplicates --")
eq("listen(touch, f) again is refused", false, event.listen("touch", f))
do
  local n = 0
  for _, rec in pairs(live) do
    if rec.callback == f and rec.signal == "touch" then n = n + 1 end
  end
  eq("...and did not double-register", 1, n)
end
eq("a DIFFERENT callback on the same signal registers", true, event.listen("touch", g))

-- ── ignore removes only the pair it was given ──────────────────────
print()
print("-- ignore --")
eq("ignore(touch, f) reports success", true, event.ignore("touch", f))
do
  local signals = {}
  for _, rec in pairs(live) do
    if rec.callback == f then signals[rec.signal] = true end
  end
  test("touch is gone", not signals.touch)
  test("drag SURVIVED", signals.drag == true)
  test("drop SURVIVED", signals.drop == true)
end
do
  local gStill = false
  for _, rec in pairs(live) do
    if rec.callback == g and rec.signal == "touch" then gStill = true end
  end
  test("the other callback on touch is untouched", gStill)
end

-- The kernel must have been told the RIGHT signal, not just some signal.
do
  local sawWrong = false
  for _, rec in ipairs(kernelLog) do
    if rec[1] == "off" and rec[2] ~= "touch" then sawWrong = true end
  end
  test("kernel.event.off was called with 'touch', nothing else", not sawWrong)
end

eq("ignoring an unregistered pair reports false", false, event.ignore("scroll", f))
eq("ignoring a never-seen callback reports false", false,
  event.ignore("touch", function() end))

-- Re-listening after ignore works (the map entry was cleaned up, not left
-- behind to block it).
eq("touch can be re-registered after ignore", true, event.listen("touch", f))

-- ── Remaining signals can each be dropped in turn ──────────────────
eq("ignore(drag, f)", true, event.ignore("drag", f))
eq("ignore(drop, f)", true, event.ignore("drop", f))
eq("ignore(touch, f)", true, event.ignore("touch", f))
do
  local any = false
  for _, rec in pairs(live) do if rec.callback == f then any = true end end
  test("nothing of f is left registered", not any)
end

-- ── The sensitive-signal denylist still holds ──────────────────────
print()
print("-- the #SEC C5 denylist is unchanged --")
eq("key_down cannot be listened for", false, (event.listen("key_down", f)))
eq("modem_message cannot be listened for", false, (event.listen("modem_message", f)))
eq("tos_shutdown cannot be pushed", false, (event.push("tos_shutdown")))
eq("an ordinary signal can still be pushed", true, (event.push("my_signal")))

-- ── Bad arguments are refused, not crashed on ──────────────────────
eq("listen with a non-function is refused", false, (event.listen("touch", "nope")))
eq("listen with a non-string name is refused", false, (event.listen(42, f)))
eq("ignore with a non-function is refused", false, (event.ignore("touch", "nope")))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
