-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: GPU↔screen pairing (seat binding)        ║
-- ║                                                            ║
-- ║  screen._pair must PREFER each GPU's current screen so the ║
-- ║  session stays on the boot/splash panel and a hot-plugged  ║
-- ║  screen doesn't yank a live seat onto it. GPUs with no      ║
-- ║  valid current screen get the remaining screens in order.  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_screen_pair.lua

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

package.loaded["component"] = { list = function() return function() return nil end end,
                                proxy = function() return nil end, invoke = function() end }
package.loaded["computer"] = { uptime = function() return 0 end }

local here = (arg and arg[0]) or "usr/lib/tests/test_screen_pair.lua"
local base = here:gsub("[^/\\]*$", "")
local screen
for _, p in ipairs({ base .. "../../../tos/kernel/screen.lua",
    "tos/kernel/screen.lua", "TOS-Dev/tos/kernel/screen.lua" }) do
  local chunk = loadfile(p); if chunk then screen = chunk(); break end
end
if not screen or not screen._pair then
  print("FAIL: could not load screen.lua / _pair missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Sorted local screens (screen.init sorts addresses).
local A, B = "aaaa-screen", "bbbb-screen"
local SCREENS = { A, B }

print("=== GPU↔screen pairing Tests ===")
print()

-- Boot: the single GPU is bound to screen B (the splash panel). It must KEEP
-- B, not get yanked onto the sorted-first screen A.
local r1 = screen._pair({ B }, SCREENS)
test("single GPU keeps its boot screen (B, not A)", B, r1[1])

-- A GPU with no current binding (false) falls back to the sorted-first free
-- screen. (false, not nil — a nil hole would truncate the array length.)
local r2 = screen._pair({ false }, SCREENS)
test("unbound GPU gets sorted-first screen (A)", A, r2[1])

-- Two GPUs each keep their own current screens (true 2-seat).
local r3 = screen._pair({ B, A }, SCREENS)
test("GPU1 keeps B", B, r3[1])
test("GPU2 keeps A", A, r3[2])

-- A GPU bound to a screen that's no longer available gets a free one.
local r4 = screen._pair({ "gone-screen" }, SCREENS)
test("GPU on a vanished screen gets a live screen", A, r4[1])

-- Two GPUs claiming the SAME current screen: first keeps it, second gets free.
local r5 = screen._pair({ A, A }, SCREENS)
test("dup-claim: GPU1 keeps A", A, r5[1])
test("dup-claim: GPU2 gets the other (B)", B, r5[2])

-- More GPUs than screens: the extra GPU gets no screen (nil result).
local r6 = screen._pair({ A, B, false }, SCREENS)
test("extra GPU beyond screen count is unpaired", nil, r6[3])

-- Hot-plug stability: GPU already on B, a new screen A appears → still B.
local r7 = screen._pair({ B }, { A, B })
test("hot-plug doesn't move a live seat", B, r7[1])

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
