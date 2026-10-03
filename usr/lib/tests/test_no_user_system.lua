-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: no user system means power off, not a loop   ║
-- ║                                                                ║
-- ║  On a 512 KB machine low memory skips the user system at boot, ║
-- ║  and the login refuses everyone -- correctly: there is no       ║
-- ║  fallback password. It then REBOOTED by itself, into the same   ║
-- ║  memory, the same skip and the same refusal: a loop with no     ║
-- ║  end, seen on the headless machine. Now it says what is needed  ║
-- ║  and waits for a key; the caller powers off.                    ║
-- ║                                                                ║
-- ║  noUserSystem is LIFTED from tos/kernel/init.lua and run        ║
-- ║  against a fake 50-column (Tier 1) screen.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_no_user_system.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local src = assert(io.open("tos/kernel/init.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local body = src:match("(local function noUserSystem.-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
test("found noUserSystem", body ~= nil)
if not body then print("*** TESTS FAILED ***"); os.exit(1) end
local noUserSystem = assert(load(body .. "\nreturn noUserSystem", "=noUserSystem", "t"))()

-- The call site: the no-user-system branch must power off, not reboot.
local branch = src:match("if not usersmod then(.-)\n    end")
test("found the minimalAuth branch", branch ~= nil)
test("...which calls noUserSystem", branch and branch:find("noUserSystem(", 1, true) ~= nil)
test("...then powers off", branch and branch:find("kernel.shutdown()", 1, true) ~= nil)
test("...and never reboots", branch and not branch:find("kernel.reboot(", 1, true), branch)

-- ── A Tier 1 screen ─────────────────────────────────────────────────
local W = 50
local lines, beeps = {}, 0
local d = {
  getTheme = function() return setmetatable({}, { __index = function(_, k) return k end }) end,
  clear = function() lines = {} end,
  set = function(x, y, text) lines[#lines + 1] = { x = x, y = y, text = text } end,
}
local queue = { { "key_up" }, { "touch" }, { nil }, { "key_down", "kb", 13, 28 } }
local pulls, timeouts = 0, {}
local function pull(t)
  pulls = pulls + 1
  timeouts[#timeouts + 1] = t
  local s = table.remove(queue, 1)
  if not s then error("waited past the key press") end
  return table.unpack(s)
end

print("=== no user system: power off, not a loop ===")
print()
noUserSystem(d, pull, function() beeps = beeps + 1 end)

local all = {}
for _, l in ipairs(lines) do all[#all + 1] = l.text end
local text = table.concat(all, " ")
test("it says memory is the problem", text:find("Not enough memory", 1, true) ~= nil, text)
test("...and how much TOS needs", text:find("1 MB", 1, true) ~= nil)
test("...and what to do", text:find("Add memory", 1, true) ~= nil)
test("...and that a key powers off", text:find("power off", 1, true) ~= nil)
test("it no longer promises a reboot will fix it", not text:lower():find("reboot", 1, true))
local widest = 0
for _, l in ipairs(lines) do widest = math.max(widest, l.x + #l.text - 1) end
test("every line fits a 50-column Tier 1 screen", widest <= W, widest)
test("it beeps once", beeps == 1, beeps)
test("only a key press ends the wait", pulls == 4, pulls)
test("...and the wait has no timeout", timeouts[1] == math.huge)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
