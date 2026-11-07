-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `redstone` says what it did                  ║
-- ║                                                                ║
-- ║  Run against a real redstone card on the headless runner for   ║
-- ║  the first time (2026-11-07): `set north abc` set 15 and said  ║
-- ║  "= abc", `set west 99` set 15 and said "= 99", `pulse` said   ║
-- ║  "Pulsed" whatever happened, refusals included, and every      ║
-- ║  refusal of the status read "No redstone component". A level   ║
-- ║  is a whole number 0-15 and a pulse 0-30 s, or nothing is      ║
-- ║  touched, and the module's own reason is shown.                ║
-- ║                                                                ║
-- ║  Drives the real command against a module that records every   ║
-- ║  call it is asked to make.                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_redstone_command.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end, freeMemory = function() return 1e6 end,
                                pullSignal = function() return nil end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
package.loaded["kernel.screen"]  = {}
package.loaded["kernel.display"] = {}

-- ── A redstone module that records what it is asked ──────────
local calls, refuse, statusErr = {}, nil, nil
package.loaded["peripheral.redstone"] = {
  status = function()
    if statusErr then return nil, statusErr end
    return { { name = "front", input = 9, output = 0 } }
  end,
  setOutput = function(side, level)
    calls[#calls + 1] = "set " .. side .. " " .. tostring(level)
    if refuse then return nil, refuse end
    if side == "sideways" then return nil, "unknown side: sideways" end
    return true
  end,
  pulse = function(side, secs)
    calls[#calls + 1] = "pulse " .. side .. " " .. tostring(secs)
    if refuse then return nil, refuse end
    return true
  end,
}

local okR, register = pcall(require, "shell.panels.commands.extras")
test("extras.lua loads", okR and type(register) == "function", register)
if not (okR and type(register) == "function") then print("*** TESTS FAILED ***"); os.exit(1) end
local S = { K = {}, E = {}, P = {}, F = {}, D = {}, U = {}, W = 80, H = 25, cwd = "/",
            T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 } }
local C = {}
register(C, S, { rp = function(p) return p end, refreshBrowser = function() end,
  adminOnly = function() return true end, rootOnly = function() return true end,
  canRead = function() return true end, canWrite = function() return true end })
test("it registers `redstone`", type(C.redstone) == "function")

local function run(...)
  calls = {}
  local out = {}
  local ok, e = pcall(C.redstone, { ... }, function(t, c) out[#out + 1] = { tostring(t), c } end)
  if not ok then out[#out + 1] = { "THREW: " .. tostring(e), 3 } end
  local text, err = {}, false
  for _, l in ipairs(out) do text[#text + 1] = l[1]; if l[2] == 3 then err = true end end
  return table.concat(text, "\n"), err
end

print("=== a level that is not 0-15 sets nothing ===")
local said, err = run("set", "north", "abc")
test("abc is refused", err and said:find("not 'abc'", 1, true) ~= nil, said)
test("and nothing was set (it set 15)", #calls == 0, table.concat(calls, ";"))
said, err = run("set", "west", "99")
test("99 is refused", err and said:find("not '99'", 1, true) ~= nil, said)
test("and nothing was set (it set 15 and said 99)", #calls == 0, table.concat(calls, ";"))
said = run("set", "north", "2.5")
test("a fraction is refused", #calls == 0 and said:find("whole number", 1, true) ~= nil, said)

print("=== a good level is set and reported as set ===")
said, err = run("set", "north", "7")
test("north 7 is set", calls[1] == "set north 7", calls[1])
test("and said so", not err and said == "Set north = 7", said)
said, err = run("set", "north", "0")
test("0 is a level too", calls[1] == "set north 0" and not err, said)
said, err = run("set", "sideways", "5")
test("the module's refusal is shown", err and said:find("unknown side", 1, true) ~= nil, said)

print("=== pulse ===")
said, err = run("pulse", "east", "zz")
test("a bad duration is refused", err and #calls == 0 and said:find("not 'zz'", 1, true) ~= nil, said)
said, err = run("pulse", "east", "45")
test("past 30 s is refused", err and #calls == 0, said)
said, err = run("pulse", "east")
test("no duration is half a second", calls[1] == "pulse east 0.5" and not err, said)
said, err = run("pulse", "east", "0.2")
test("a good one is sent and reported with its length", calls[1] == "pulse east 0.2"
  and said == "Pulsed east for 0.2 s", said)
refuse = "peripheral.redstone cap required"
said, err = run("pulse", "east", "1")
test("a refused pulse is NOT reported as pulsed", err and not said:find("Pulsed", 1, true), said)
refuse = nil

print("=== status says why it cannot read ===")
statusErr = "peripheral.redstone cap required"
said, err = run()
test("the real reason, not 'No redstone component'", err and said == "Peripheral.redstone cap required", said)
statusErr = nil
said, err = run()
test("and a working card lists its sides", not err and said:find("front", 1, true) ~= nil, said)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
