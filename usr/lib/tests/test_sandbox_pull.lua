-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: sandbox pullSignal filtering (#SEC)      ║
-- ║                                                            ║
-- ║  The sandbox used to hand out raw computer.pullSignal,     ║
-- ║  which drains the global queue (steal another seat's keys, ║
-- ║  sniff modem packets, block the machine). The safe one     ║
-- ║  YIELDS to the scheduler (so proc.tick routes only this    ║
-- ║  seat's input and other processes keep their signal copy)  ║
-- ║  and drops broadcast/control signals; seat-routed input    ║
-- ║  (key/touch) is delivered so interactive programs work.    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_pull.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- Controllable clock for the raw-fallback timeout path.
local clock = 0
package.loaded["computer"] = {
  uptime = function() return clock end,
  freeMemory = function() return 1e6 end,
  totalMemory = function() return 1e6 end,
  address = function() return "test" end,
  pushSignal = function() end,
  pullSignal = function(t) clock = clock + (tonumber(t) or 0) + 0.1; return nil end,
}
-- sandbox.lua require()s several kernel modules at build time, but the pull
-- helper itself only needs `computer`; load the module and grab the hook.
package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local sandbox = require("kernel.sandbox")
local pull = sandbox._safePullSignal
if type(pull) ~= "function" then
  print("FAIL: sandbox._safePullSignal missing")
  print("Results: 0 passed, 1 failed"); return false
end

print("=== sandbox pullSignal filtering Tests ===")
print()

-- Drive the YIELD path: run pull() in a coroutine, feed it signals via
-- resume, and observe what it yields (keep waiting) vs returns (delivers).
-- A resume value that comes back as a yield means pull() dropped it and is
-- waiting for more; a return means pull() delivered it.
local function feed(co, ...)
  local res = table.pack(coroutine.resume(co, ...))
  -- res[1] = ok; if coroutine is still suspended it yielded (dropped/waiting),
  -- if dead it returned (delivered) with the value(s) in res[2..].
  return coroutine.status(co) == "dead", table.unpack(res, 2, res.n)
end

-- ── key_down (seat-routed input) is DELIVERED ──────────────────────
do
  local co = coroutine.create(function() return pull() end)
  coroutine.resume(co)                      -- run to the first yield
  local done, name, _, ch = feed(co, "key_down", "kbaddr", 65, 30)
  test("key_down is delivered (interactive input works)", done)
  eq("delivered the right signal name", "key_down", name)
  eq("delivered the char payload", 65, ch)
end

-- ── touch (seat-routed) is DELIVERED ───────────────────────────────
do
  local co = coroutine.create(function() return pull() end)
  coroutine.resume(co)
  local done, name = feed(co, "touch", "scraddr", 4, 5, 0)
  test("touch is delivered", done)
  eq("touch name", "touch", name)
end

-- ── modem_message (broadcast) is DROPPED, then a later key delivered ─
do
  local co = coroutine.create(function() return pull() end)
  coroutine.resume(co)
  local done1 = feed(co, "modem_message", "from", "to", 1, 0, "secret payload")
  test("modem_message is NOT delivered (dropped, still waiting)", not done1)
  local done2, name = feed(co, "key_down", "kb", 97, 30)
  test("...and a following key_down IS delivered", done2)
  eq("post-drop delivery is the key", "key_down", name)
end

-- ── control signals are DROPPED ────────────────────────────────────
for _, ctl in ipairs({ "tos_shutdown", "tos_logout", "tos_login_complete",
    "tos_seat_changed", "tos_shell_exited" }) do
  local co = coroutine.create(function() return pull() end)
  coroutine.resume(co)
  local done = feed(co, ctl, "x")
  test("control signal '" .. ctl .. "' is dropped", not done)
end

-- ── nil idle resumes just keep waiting (no busy return) ────────────
do
  local co = coroutine.create(function() return pull() end)   -- no timeout
  coroutine.resume(co)
  local done = feed(co, nil)                 -- idle tick
  test("nil idle resume keeps waiting (infinite pull)", not done)
  local done2, name = feed(co, "clipboard", "kb", "pasted")
  test("clipboard (seat-routed) delivered after idle", done2)
  eq("clipboard name", "clipboard", name)
end

-- ── timeout honoured across dropped signals ────────────────────────
do
  clock = 100
  local co = coroutine.create(function() return pull(0.5) end)
  coroutine.resume(co)
  -- Two modem messages arrive but the deadline (100.5) passes between them.
  local d1 = feed(co, "modem_message", "a")
  test("timed pull: first modem dropped, still waiting", not d1)
  clock = 101                                -- past the 0.5s deadline
  local d2, ret = feed(co, "modem_message", "b")
  test("timed pull returns after deadline", d2)
  eq("timed-out pull returns nil", nil, ret)
end

-- ── Raw fallback (no coroutine): ceiling + nil ─────────────────────
do
  clock = 0
  -- Not inside a coroutine → the raw branch runs; our stub pullSignal only
  -- ever returns nil, so this must terminate at the ceiling, not hang.
  local ret = pull(0)
  eq("raw fallback returns nil without hanging", nil, ret)
  test("raw fallback respected a finite clock advance", clock > 0)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
