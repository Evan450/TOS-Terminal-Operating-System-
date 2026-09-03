-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: panels state seat-index resolution       ║
-- ║                                                            ║
-- ║  S.displayIdx must survive a ctx that forgot to thread it  ║
-- ║  (the old `tui` command did): fall back to asking the      ║
-- ║  kernel handle. A nil seat index on tos_logout used to     ║
-- ║  read as GLOBAL logout, which broke the kernel loop and    ║
-- ║  POWERED OFF the machine ("logout shuts down" repro).      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_state_seat.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }

local state = require("shell.panels.state")

local function ctxBase(extra)
  local ctx = {
    D = {
      getTheme   = function() return { fg = 1, bg = 2 } end,
      getGpuTier = function() return 2 end,
      getSize    = function() return 80, 25 end,
    },
    W = 80, H = 25,
  }
  for k, v in pairs(extra or {}) do ctx[k] = v end
  return ctx
end

print("=== panels state seat-index Tests ===")
print()

-- Explicit ctx.displayIdx wins.
local S = state.new(ctxBase({ displayIdx = 5,
  K = { getDisplayIdx = function() return 2 end } }))
eq("explicit ctx.displayIdx wins", 5, S.displayIdx)

-- Missing from ctx -> derived from the kernel handle (the `tui` gap).
S = state.new(ctxBase({ K = { getDisplayIdx = function() return 2 end } }))
eq("falls back to K.getDisplayIdx", 2, S.displayIdx)

-- No kernel handle either -> stays nil (emergency contexts), no crash.
S = state.new(ctxBase({ K = {} }))
eq("no source -> nil, no crash", nil, S.displayIdx)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
