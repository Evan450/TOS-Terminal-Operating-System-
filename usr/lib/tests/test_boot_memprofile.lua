-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the per-stage boot memory profile            ║
-- ║                                                                ║
-- ║  THE RAM FLOOR IS 1 MB asked for a per-stage memory profile    ║
-- ║  before any footprint work. A raw freeMemory() mid-boot is     ║
-- ║  mostly garbage, and OpenComputers gives the guest no          ║
-- ║  collectgarbage -- but its machine loop collects every 10      ║
-- ║  resumes. memMark (tos/kernel/init.lua) yields ten times,      ║
-- ║  pushing back what it pops, then reads. Off unless boot.cfg    ║
-- ║  says memprofile = true.                                       ║
-- ║                                                                ║
-- ║  memMark is LIFTED from init.lua and run against a fake        ║
-- ║  computer.                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_boot_memprofile.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readSrc(rel)
  for _, p in ipairs({ rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n")) end
  end
end
local src = assert(readSrc("tos/kernel/init.lua"), "tos/kernel/init.lua")
local block = src:match("(  local bootMem = .-\n  end\n)")
test("memMark is in tos/kernel/init.lua", block ~= nil)
if not block then print("*** TESTS FAILED ***"); return false end

-- Build memMark in an env holding a fake computer and the given boot.cfg.
local function build(bootCfg, withGC)
  local queue = { { "component_added", "abc", "screen" }, { "key_down", "kb", 97, 30 } }
  local pulls, pushed = 0, {}
  local free = 400 * 1024
  local computer = {
    pullSignal = function()
      pulls = pulls + 1
      local s = table.remove(queue, 1)
      if s then return table.unpack(s) end
    end,
    pushSignal = function(...) pushed[#pushed + 1] = { ... } end,
    freeMemory = function() return free end,
    uptime = function() return 12.5 end,
  }
  local env = setmetatable({ computer = computer, bootCfg = bootCfg,
    collectgarbage = withGC }, { __index = _G })
  -- false, not nil: nil would fall through __index to the host's real one.
  if not withGC then env.collectgarbage = false end
  local chunk = assert(load(block .. "\nreturn memMark, function() return bootMem end",
    "=memMark", "t", env))
  local memMark, getMem = chunk()
  return memMark, getMem, function() return pulls, pushed end
end

print("=== boot memory profile ===")
print()

do
  local memMark, getMem, stats = build(nil)
  memMark("1 core modules")
  test("off by default: nothing recorded", getMem() == nil)
  test("...and nothing pulled from the signal queue", stats() == 0)
  local memMark2, getMem2 = build({ memprofile = "yes" })
  memMark2("x")
  test("only memprofile = true turns it on", getMem2() == nil)
end

do
  local memMark, getMem, stats = build({ memprofile = true })
  memMark("3 filesystem")
  local m = getMem()
  test("on: a stage is recorded with its free memory",
    m and m[1] and m[1].stage == "3 filesystem" and m[1].free == 400 * 1024)
  local pulls, pushed = stats()
  test("without collectgarbage it yields ten times (OC's machine collects every 10)", pulls == 10, pulls)
  test("...and pushes back every signal it popped, in order",
    #pushed == 2 and pushed[1][1] == "component_added" and pushed[2][1] == "key_down"
    and pushed[2][3] == 97)
end

do
  local gcCalls = 0
  local memMark, getMem, stats = build({ memprofile = true }, function() gcCalls = gcCalls + 1 end)
  memMark("5 event system")
  test("with collectgarbage it collects instead of yielding", gcCalls == 1 and stats() == 0)
end

do
  local _, n = src:gsub('\n  memMark%("', "")
  test("every boot stage is marked", n >= 15, n)
  test("the profile is logged and kept at boot complete",
    src:find('_G._TOS.bootMem = bootMem', 1, true) ~= nil
    and src:find('log.info("memprofile"', 1, true) ~= nil)
  -- A mark is taken as its stage STARTS: a stage's cost is its own mark
  -- minus the next one. The first version printed each mark against the
  -- previous one, so every stage's cost landed on the stage after it.
  test("a stage's cost is charged to that stage (its mark minus the next)",
    src:find("(m.free - nxt.free)", 1, true) ~= nil)
  local core = readSrc("tos/shell/panels/commands/core.lua") or ""
  test("`mem --boot` prints it", core:find('args[1] == "--boot"', 1, true) ~= nil
    and core:find("_G._TOS.bootMem", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
