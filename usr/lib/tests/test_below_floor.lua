-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: below TOS's 1 MB floor, it says add memory   ║
-- ║                                                                ║
-- ║  At 768 KB (headless runner, T1, 2026-11-07) the command line  ║
-- ║  starts, says only that the full interface needs 1536 KB, and  ║
-- ║  then every command fails with "free RAM (close tabs /         ║
-- ║  reboot) and they'll load on next use" -- advice that can      ║
-- ║  never work on that machine (17 KB free after the shell).      ║
-- ║  bootcfg.FLOOR_KB is the floor the README states; below it the ║
-- ║  CLI says so at start and every memory refusal says add        ║
-- ║  memory. The TODO's support-ceiling policy: "refuse ... or     ║
-- ║  fall back to the CLI shell", the CLI being what TOS does.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_below_floor.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readSrc(p)
  local h = assert(io.open(p, "rb")); local s = h:read("a"); h:close()
  return (s:gsub("\r\n", "\n"))
end

local totalKB = 768
package.loaded["computer"] = { totalMemory = function() return totalKB * 1024 end,
  freeMemory = function() return 17 * 1024 end, uptime = function() return 0 end }
local bcfg = dofile("tos/kernel/bootcfg.lua")

print("=== bootcfg.belowFloor ===")
test("the floor is 1024 KB", bcfg.FLOOR_KB == 1024, bcfg.FLOOR_KB)
test("768 KB is below it", bcfg.belowFloor() == 768, bcfg.belowFloor())
totalKB = 1024
test("1024 KB is not", bcfg.belowFloor() == nil, bcfg.belowFloor())
totalKB = 2048
test("2048 KB is not", bcfg.belowFloor() == nil)
test("the README states the same floor",
  readSrc("README.md"):find("1 MB of memory", 1, true) ~= nil)

print("=== the executor's advice ===")
do
  local src = readSrc("tos/shell/panels/executor.lua")
  local body = src:match("(local function memoryAdvice%(%).-\n  end\n)")
  test("found memoryAdvice", body ~= nil)
  if body then
    package.loaded["kernel.bootcfg"] = bcfg
    local env = setmetatable({ package = package }, { __index = _G })
    local advice = assert(load(body .. "\nreturn memoryAdvice", "=advice", "t", env))()
    totalKB = 768
    test("below the floor: add memory", advice():find("This machine has 768 KB and TOS needs 1024 KB: add memory.", 1, true) ~= nil, advice())
    totalKB = 1280
    test("above it: free some memory", advice():find("close tabs", 1, true) ~= nil, advice())
    package.loaded["kernel.bootcfg"] = nil
    test("with no bootcfg loaded it still answers", type(advice()) == "string")
  end
  local uses = select(2, src:gsub("o%(memoryAdvice%(%), T%.dim%)", ""))
  test("both unloadable-command messages use it", uses == 2, uses)
  test("no fixed 'close tabs, or reboot' line is left", not src:find('o("Free some memory', 1, true))
end

print("=== the dispatcher's out-of-memory line and the CLI's start ===")
do
  local cmds = readSrc("tos/shell/panels/commands.lua")
  local at = cmds:find("commands need more memory than is free", 1, true)
  local before = at and cmds:sub(math.max(1, at - 900), at) or ""
  test("the dispatcher asks belowFloor before it advises", before:find("belowFloor", 1, true) ~= nil)
  test("and says add memory below it", cmds:find("TOS needs %d KB: add memory", 1, true) ~= nil)
  local cli = readSrc("tos/shell/cli.lua")
  test("the CLI says so at start", cli:find("bcfg.belowFloor", 1, true) ~= nil
    and cli:find("so most commands will not load. Add memory.", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
