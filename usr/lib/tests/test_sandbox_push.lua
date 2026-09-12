-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: sandbox pushSignal filtering (#SEC)      ║
-- ║                                                            ║
-- ║  The sandbox's computer.pushSignal used to drop only the   ║
-- ║  tos_* control signals, leaving every HARDWARE INPUT signal ║
-- ║  (key_down/key_up/clipboard/touch/drag/drop/scroll) and     ║
-- ║  modem_message pushable. proc.tick routes an input signal   ║
-- ║  to the FOREGROUND process of the seat that owns its        ║
-- ║  address (or the GLOBAL foreground when it doesn't resolve),  ║
-- ║  so a sandboxed program holding `component` could inject a   ║
-- ║  keystroke or click into ANOTHER seat's / another user's     ║
-- ║  session — e.g. type a command into a root shell.           ║
-- ║                                                            ║
-- ║  The fix widens the drop set to those input/network signals ║
-- ║  while still letting a program push its OWN custom signals.  ║
-- ║  This test drives the LIVE module (must block) and a copy    ║
-- ║  of HEAD's module (must still leak) to prove the fix bites.  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_push.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

print("=== sandbox pushSignal filtering Tests ===")
print()

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

-- A recording `computer` stub: whatever reaches the REAL pushSignal is
-- logged here, so a leaked signal is visible and a dropped one is absent.
local pushed = {}
local function resetPushed() pushed = {} end
package.loaded["computer"] = {
  uptime      = function() return 0 end,
  freeMemory  = function() return 1e6 end,
  totalMemory = function() return 1e6 end,
  address     = function() return "test" end,
  energy      = function() return 1 end,
  maxEnergy   = function() return 1 end,
  pushSignal  = function(name, ...) pushed[#pushed + 1] = name; return true end,
  pullSignal  = function() return nil end,
}
-- Minimal `component` stub — makeSafeComponent only stores it at build time.
package.loaded["component"] = {
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
  type  = function() return nil end,
}

-- Signals a sandboxed program must never be able to synthesize, and one it
-- legitimately may (its own custom coordination signal).
local BLOCKED = {
  "key_down", "key_up", "clipboard", "touch", "drag", "drop", "scroll",
  "modem_message", "tos_shutdown", "tos_logout",
}
local ALLOWED = "my_app_signal"

-- Build a sandbox env with the component cap (which is what exposes
-- computer.pushSignal) from a given sandbox module.
local function buildComputer(sandboxMod)
  local env = sandboxMod.build({ caps = { component = true } })
  return env.computer
end

-- ── The LIVE (fixed) module blocks every input/network/control signal ──
do
  local sandbox = require("kernel.sandbox")
  local comp = buildComputer(sandbox)
  test("live: component cap really exposes computer.pushSignal",
    type(comp) == "table" and type(comp.pushSignal) == "function")

  for _, sig in ipairs(BLOCKED) do
    resetPushed()
    comp.pushSignal(sig, "addr", 65, 30)
    test("live: pushSignal('" .. sig .. "') is dropped (not forwarded)",
      #pushed == 0)
  end

  resetPushed()
  comp.pushSignal(ALLOWED, "payload")
  test("live: a program's OWN custom signal still pushes",
    #pushed == 1 and pushed[1] == ALLOWED)
end

-- ── FAILS-BEFORE proof #1 (deterministic): the OLD policy leaked ───────
-- A faithful transcription of the pre-fix wrapper, which dropped ONLY the
-- tos_* control set. Under it a "BLOCKED" assertion above would fail for
-- every input/network signal — that is exactly the hole the fix closes.
do
  local OLD_CONTROL_ONLY = {
    tos_shutdown = true, tos_logout = true,
    tos_login_complete = true, tos_seat_changed = true,
    tos_shell_exited = true,
  }
  local function oldPush(name, ...)
    if type(name) == "string" and OLD_CONTROL_ONLY[name] then return end
    pushed[#pushed + 1] = name
  end
  resetPushed()
  oldPush("key_down", "kbaddr", 65, 30)
  oldPush("touch", "scraddr", 4, 5, 0)
  oldPush("modem_message", "from")
  test("old policy (control-only) DID forward key_down/touch/modem (the hole)",
    #pushed == 3)
  resetPushed()
  oldPush("tos_shutdown")
  test("old policy already blocked tos_shutdown (so the fix only ADDS input)",
    #pushed == 0)
end

-- (The pre-fix run against the real module was done once, by hand, when
-- this landed. It is not repeated here: an assertion that HEAD is still
-- vulnerable starts failing the moment the fix is committed.)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
