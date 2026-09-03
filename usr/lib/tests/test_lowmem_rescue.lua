-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: you can always reboot                       ║
-- ║                                                                ║
-- ║  Reported from a real machine: on a box short of RAM the       ║
-- ║  `core` category fails to load, and `help`, `reboot` and       ║
-- ║  `shutdown` stop existing.                                     ║
-- ║                                                                ║
-- ║  Those three live in `core`, which is the biggest command file ║
-- ║  in the tree — so on a tight box it is precisely the one that  ║
-- ║  fails: reading it wants a large contiguous buffer and a       ║
-- ║  machine at ~56 KB free has not got one. The dispatcher        ║
-- ║  returned nil and the operator was advised to free some memory ║
-- ║  and try again — by closing tabs, or rebooting. Which is the   ║
-- ║  command that had just failed.                                 ║
-- ║                                                                ║
-- ║  That is a TRAP, not a wording problem. The advice was correct ║
-- ║  and impossible to follow. An earlier pass fixed the message   ║
-- ║  (it used to say "unknown command", which was worse); this     ║
-- ║  fixes the thing the message was about.                        ║
-- ║                                                                ║
-- ║  The escape hatch must not need the thing that broke, so       ║
-- ║  reboot / shutdown / help / mem are now served from the        ║
-- ║  dispatcher itself, which is already loaded by the time any of ║
-- ║  this can happen — and only when the real one is missing, so   ║
-- ║  a healthy box is unaffected.                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_lowmem_rescue.lua   (from the TOS-Dev root)

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

local here = (arg and arg[0]) or "usr/lib/tests/test_lowmem_rescue.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path

local FREE, TOTAL = 56 * 1024, 192 * 1024   -- the box it was reported on
package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return FREE end,
  totalMemory = function() return TOTAL end,
  pullSignal = function() return nil end, beep = function() end,
  shutdown = function(reboot) error("RAW_SHUTDOWN:" .. tostring(reboot), 0) end,
}
package.loaded["component"] = { list = function() return function() end end,
  proxy = function() end, isAvailable = function() return false end }

local Cmds = require("shell.panels.commands")

-- ── A shell state just rich enough for the dispatcher ──────────────
local powered = nil
local function makeState(tier)
  powered = nil
  local S
  S = {
    T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
    W = 80, H = 25, tier = tier, userTier = tier, st = nil, U = nil,
    K = {
      getLog   = function() return nil end,
      reboot   = function() powered = "reboot" end,
      shutdown = function() powered = "shutdown" end,
    },
    E = { push = function() end }, P = {}, F = {}, SC = nil, NM = nil,
    who = "evan", cwd = "/", tabs = { { type = "shell" } }, activeTab = 1,
    browser = { path = "/", sel = 1, scroll = 0, files = {} },
  }
  return S
end
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return nil end,
}
local function collector()
  local buf = {}
  return buf, function(text, color) buf[#buf + 1] = tostring(text) end
end
local function joined(buf) return table.concat(buf, "\n") end

print("=== low-memory rescue Tests ===")
print()

-- ── Healthy box: the REAL commands must win ────────────────────────
print("-- with enough memory, nothing changes --")
do
  local S = makeState(3)
  local C = Cmds.build(S, deps)
  test("reboot resolves", type(C.reboot) == "function")
  local buf, o = collector()
  C.reboot({}, o)
  eq("...and it reboots", "reboot", powered)
  test("...via the REAL command, not the rescue (no rescue notice)",
    joined(buf):find("rescue", 1, true) == nil)

  local S2 = makeState(3)
  local C2 = Cmds.build(S2, deps)
  local buf2, o2 = collector()
  C2.shutdown({}, o2)
  eq("shutdown shuts down", "shutdown", powered)
  test("...also the real one", joined(buf2):find("rescue", 1, true) == nil)
end

-- ── Now starve it: `core` cannot be read ───────────────────────────
-- package.preload is consulted before the searchers, so this makes
-- require() fail exactly the way a low-memory read does — and, like the
-- real thing, it fails EVERY time rather than being cached.
print()
print("-- with `core` unable to load --")
package.loaded["shell.panels.commands.core"] = nil
package.preload["shell.panels.commands.core"] = function()
  error("not enough memory", 0)
end

do
  local S = makeState(3)
  local C = Cmds.build(S, deps)

  test("reboot STILL resolves", type(C.reboot) == "function")
  test("shutdown still resolves", type(C.shutdown) == "function")
  test("help still resolves", type(C.help) == "function")
  test("mem still resolves", type(C.mem) == "function")

  local buf, o = collector()
  C.reboot({}, o)
  eq("reboot actually reboots", "reboot", powered)
  test("...and says it is the rescue path",
    joined(buf):lower():find("rescue", 1, true) ~= nil)

  local S2 = makeState(3)
  local C2 = Cmds.build(S2, deps)
  local buf2, o2 = collector()
  C2.shutdown({}, o2)
  eq("shutdown actually shuts down", "shutdown", powered)

  -- help must still name commands, from the registry, without loading one.
  local S3 = makeState(3)
  local C3 = Cmds.build(S3, deps)
  local buf3, o3 = collector()
  C3.help({}, o3)
  local text = joined(buf3)
  test("help produced output", #buf3 > 0)
  test("...naming reboot", text:find("reboot", 1, true) ~= nil)
  test("...naming shutdown", text:find("shutdown", 1, true) ~= nil)
  test("...and saying it is degraded",
    text:lower():find("rescue", 1, true) ~= nil)

  -- mem is the number that decides close-a-tab vs reboot.
  local S4 = makeState(3)
  local C4 = Cmds.build(S4, deps)
  local buf4, o4 = collector()
  C4.mem({}, o4)
  test("mem reports the free figure (" .. joined(buf4) .. ")",
    joined(buf4):find("56", 1, true) ~= nil)

  -- A command with no rescue must still be absent — this is a narrow
  -- escape hatch, not a second implementation of the shell.
  test("an ordinary core command is still missing", C.cat == nil)
  test("...and so is a random name", C.definitely_not_a_command == nil)
end

-- ── The gate still holds ───────────────────────────────────────────
-- The rescue must not become a way for a guest to power off a machine
-- other people are using.
print()
print("-- the rescue is not a privilege hole --")
do
  _G._TOS = _G._TOS or {}
  _G._TOS.shellPIDs = { [1] = 11, [2] = 22 }   -- two operators logged in
  local S = makeState(0)                        -- guest
  local C = Cmds.build(S, deps)
  local buf, o = collector()
  C.reboot({}, o)
  eq("a guest cannot reboot a machine others are using", nil, powered)
  test("...and is told why", #buf > 0)

  _G._TOS.shellPIDs = { [1] = 11 }              -- sole operator
  local S2 = makeState(0)
  local C2 = Cmds.build(S2, deps)
  local buf2, o2 = collector()
  C2.reboot({}, o2)
  eq("the sole operator may reboot even as a guest", "reboot", powered)
  _G._TOS.shellPIDs = nil
end

-- ── Recovery: once memory frees, the real commands come back ───────
-- The OOM path deliberately does not cache the failure. If it did, a box
-- that recovered would stay crippled until reboot — which is the trap
-- again, one level up.
print()
print("-- and it heals --")
package.preload["shell.panels.commands.core"] = nil
package.loaded["shell.panels.commands.core"] = nil
do
  local S = makeState(3)
  local C = Cmds.build(S, deps)
  local buf, o = collector()
  C.reboot({}, o)
  eq("reboot works again", "reboot", powered)
  test("...and it is the REAL one again, not the rescue",
    joined(buf):find("rescue", 1, true) == nil)
  test("the ordinary core commands are back", type(C.cat) == "function")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
