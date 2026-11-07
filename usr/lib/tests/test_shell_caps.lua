-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the shell holds the caps it is given         ║
-- ║                                                                ║
-- ║  spawnShellForSeat runs inside the login process, which holds  ║
-- ║  no caps, and process.spawn intersects a child's caps with its ║
-- ║  parent's. So every cap in shellCaps was stripped, and the     ║
-- ║  2026-08-11 fix that added the peripheral caps never took      ║
-- ║  effect: on the headless runner with a real redstone card,     ║
-- ║  `redstone` said "No redstone component" and `redstone set`    ║
-- ║  "peripheral.redstone cap required", as root. The same held    ║
-- ║  for `robot` and `inventory`. The shell is spawned with        ║
-- ║  inherit = false now: the kernel grants its caps.              ║
-- ║                                                                ║
-- ║  Drives the real kernel/process.lua for the rule, and pins     ║
-- ║  kernel/init.lua's spawn.                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_shell_caps.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["kernel.event"] = { removeSource = function() end }
debug = nil

local here = (arg and arg[0]) or "usr/lib/tests/test_shell_caps.lua"
local base = here:gsub("[^/\\]*$", "")
local proc
for _, p in ipairs({ base .. "../../../tos/kernel/process.lua", "tos/kernel/process.lua" }) do
  local chunk = loadfile(p); if chunk then proc = chunk(); break end
end
test("process.lua loads", proc ~= nil)
if not proc then print("*** TESTS FAILED ***"); os.exit(1) end

print("=== a child of a capless login ===")
local SHELL_CAPS = { ["fs.read"] = true, ["peripheral.redstone"] = true }
local inheriting, granted
-- The login, as the kernel spawns it: no caps of its own.
proc.spawn("login@1", function()
  inheriting = proc.spawn("shell-inheriting", function() coroutine.yield() end,
    { caps = SHELL_CAPS, display = 1 })
  granted = proc.spawn("shell-granted", function() coroutine.yield() end,
    { caps = SHELL_CAPS, display = 1, inherit = false })
  coroutine.yield()
end, { display = 1, source = "kernel" })
for _ = 1, 5 do proc.tick() end

local a, b = inheriting and proc.get(inheriting), granted and proc.get(granted)
test("both were spawned", a ~= nil and b ~= nil)
test("inheriting from the login strips every cap (the bug's mechanism)",
  a and a.caps and next(a.caps) == nil, a and a.caps and next(a.caps))
test("inherit = false keeps peripheral.redstone", b and b.caps and b.caps["peripheral.redstone"] == true)
test("...and fs.read", b and b.caps and b.caps["fs.read"] == true)
test("the parent link is still recorded either way", b and a and b.parent == a.parent and b.parent ~= nil,
  b and b.parent)

print("=== the kernel spawns the shell that way ===")
do
  local h = assert(io.open("tos/kernel/init.lua", "rb"))
  local src = h:read("a"):gsub("\r\n", "\n"); h:close()
  local at = src:find("spawnShellForSeat = function(dIdx, token)", 1, true)
  local stop = at and src:find("\n  end\n", at, true)
  local body = at and src:sub(at, stop or #src) or ""
  test("found spawnShellForSeat", at ~= nil)
  local spawnOpts = body:match("caps%s*=%s*shellCaps,(.-)}%)")
  test("its spawn grants shellCaps", spawnOpts ~= nil)
  test("with inherit = false", spawnOpts and spawnOpts:find("inherit%s*=%s*false") ~= nil, spawnOpts)
  test("shellCaps still carries the peripheral caps",
    src:find('%["peripheral%.redstone"%]%s*=%s*true') ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
