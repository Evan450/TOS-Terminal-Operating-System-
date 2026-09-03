-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `sudo <cmd>` reports failures instead of    ║
-- ║  failing to report them                                       ║
-- ║                                                                ║
-- ║  sudoRunElevated wraps the elevated command in a pcall so a    ║
-- ║  command that throws can never leave the shell sitting at root ║
-- ║  — the restore runs on every path, then the error is printed.  ║
-- ║                                                                ║
-- ║  Except the printing half never worked. `o` is a PARAMETER of  ║
-- ║  each command body (C.sudo = function(args, o)), not a file    ║
-- ║  local, so the helper's `o("sudo: "..err)` read a nil GLOBAL   ║
-- ║  and raised "attempt to call a nil value" — swallowing the     ║
-- ║  real error and replacing it with a worse one, on the exact    ║
-- ║  path an operator most needs to be told what happened.         ║
-- ║                                                                ║
-- ║  What is pinned here:                                          ║
-- ║   * a thrown elevated command produces a "sudo: ..." LINE      ║
-- ║     rather than an error out of C.sudo                         ║
-- ║   * the original error text survives into that line            ║
-- ║   * the privilege restore still happens on the throwing path   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sudo_report.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.path = "tos/?.lua;tos/?/init.lua;../../../tos/?.lua;"
  .. "../../../tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

-- Off-box stand-ins for the two OC libraries core.lua requires at load.
package.loaded["computer"]  = { uptime = function() return 0 end,
                                freeMemory = function() return 1e6 end,
                                beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }

local okC, register = pcall(require, "shell.panels.commands.core")
if not okC or type(register) ~= "function" then
  print("FAIL: could not load shell/panels/commands/core.lua: " .. tostring(register))
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED *** "); return false
end

print("=== sudo failure reporting Tests ===")
print()

-- ── The smallest shell state C.sudo actually reads ─────────────────
local ROOT_TIER, USER_TIER = 3, 1
local restored = {}          -- what sudoRunElevated put back

local loginSess = { user = "alice", tier = USER_TIER, home = "/home/alice" }
local elevSess  = { user = "alice", tier = ROOT_TIER, elevated = true }

local U = {
  TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 },
  getSession      = function() return loginSess end,
  currentSession  = function() return loginSess end,
  elevationInfo   = function() return { configured = true, cap = ROOT_TIER } end,
  elevate         = function(_, pw)
    if pw == "letmein9" then return elevSess end
    return nil, "wrong elevation password"
  end,
  registerSession = function() return "ELEVTOKEN" end,
  logout          = function(tok) restored.loggedOut = tok; return true end,
}

local S = {
  K = {}, E = { push = function() end }, P = {}, F = {}, D = {}, U = U,
  SC = nil, NM = nil, st = "LOGINTOKEN",
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = USER_TIER, W = 80, H = 25, cwd = "/home/alice",
  displayIdx = 1,
}

-- promptInput is a dep, so the test supplies the password without a screen.
local prompts = {}
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function(label) prompts[#prompts + 1] = label; return "letmein9" end,
}

local C = {}
local okR, rerr = pcall(register, C, S, deps)
test("core.lua registers its commands", okR)
if not okR then
  print("  registration error: " .. tostring(rerr))
  print(string.format("Results: %d passed, %d failed", passed, failed + 1))
  print("*** TESTS FAILED ***"); return false
end
test("C.sudo exists", type(C.sudo) == "function")

-- ── The throwing elevated command ──────────────────────────────────
-- S.execOne is what actually runs the rest of the line. Making it throw
-- is the whole point: that is the path that used to crash while trying
-- to report the crash.
local THROWN = "disk exploded"
S.execOne = function() error(THROWN, 0) end

local buf = {}
local function o(text, color) buf[#buf + 1] = { text, color } end

local okSudo, sudoErr = pcall(C.sudo, { "rm", "-rf", "/" }, o)
test("C.sudo does not itself error when the elevated command throws", okSudo)
if not okSudo then print("  raised: " .. tostring(sudoErr)) end

local reported
for _, line in ipairs(buf) do
  if type(line[1]) == "string" and line[1]:sub(1, 6) == "sudo: " then reported = line[1] end
end
test("a 'sudo: ...' line was produced", reported ~= nil)
test("...carrying the original error text ("
  .. tostring(reported) .. ")", reported ~= nil and reported:find(THROWN, 1, true) ~= nil)

-- The regression this replaced: the failure was reported as a nil-call.
test("the report is NOT a 'nil value' crash message",
  reported == nil or reported:find("nil value", 1, true) == nil)

-- ── Privilege restore still happens on the throwing path ───────────
eq("the shell token is restored after the throw", "LOGINTOKEN", S.st)
eq("the elevated session is logged out", "ELEVTOKEN", restored.loggedOut)
test("no persistent elevation was left behind", S._sudo == nil)

-- ── The success path still prints the command's output ─────────────
S.execOne = function() return { { "hello from root", S.T.fg } } end
buf = {}
local okOK = pcall(C.sudo, { "whoami" }, o)
test("a successful elevated command runs cleanly", okOK)
local echoed = false
for _, line in ipairs(buf) do
  if line[1] == "hello from root" then echoed = true end
end
test("...and its output reaches the shell", echoed)
eq("the shell token is restored after success too", "LOGINTOKEN", S.st)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
