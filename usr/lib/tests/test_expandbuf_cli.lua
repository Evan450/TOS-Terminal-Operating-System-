-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the command line wraps at its own width      ║
-- ║                                                                ║
-- ║  expandBuf wraps a command's output 6 columns short on a T2+   ║
-- ║  screen, to leave room for a view tab's line-number gutter.    ║
-- ║  The command line draws no gutter, so everything it showed     ║
-- ║  through the buffer (a pipe, a status line) wrapped at 74 on   ║
-- ║  an 80-column screen: sudo's 78-character usage broke in two   ║
-- ║  on the headless machine. The full interface keeps the room.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_expandbuf_cli.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
local helpers = require("shell.panels.helpers")

local usage = "Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off"
local function rows(S)
  local out = helpers.expandBuf(S, { { usage, 1 } })
  return #out, out
end

print("=== a 78-character line on an 80-column T2 screen ===")
local n = rows({ W = 80, tier = 2, isCLI = true })
test("at the command line it stays one line", n == 1, n)
local n2 = rows({ W = 80, tier = 2 })
test("in the full interface it still leaves the gutter room", n2 == 2, n2)
local n3 = rows({ W = 80, tier = 1, isCLI = true })
test("a T1 screen never reserved any", n3 == 1, n3)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
