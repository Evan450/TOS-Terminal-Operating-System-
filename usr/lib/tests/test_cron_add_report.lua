-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `cron add` says what went wrong             ║
-- ║                                                               ║
-- ║  On a headless machine `cron add bad 0 print("x")` put a raw  ║
-- ║  Lua error on the screen: cron.add answers (nil, reason), and ║
-- ║  the command concatenated the nil. And a job's script is Lua  ║
-- ║  or a path to a .lua file, never a shell line, but nothing    ║
-- ║  said so: the manual's own example, `run /home/me/backup.lua`,║
-- ║  would have been stored and failed with a syntax error at     ║
-- ║  every interval, for ever, in a log nobody was reading.       ║
-- ║  Drives the real command against the real scheduler.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cron_add_report.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end, freeMemory = function() return 1048576 end,
                                totalMemory = function() return 2097152 end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }

local files = {}
local F = {
  readFile = function(p) return files[p] end,
  writeFile = function(p, d) files[p] = d; return true end,
  writeFileAtomic = function(p, d) files[p] = d; return true end,
  exists = function(p) return files[p] ~= nil end,
  normalize = function(p) return p end,
}
local EV = { timer = function() return 1 end, cancelTimer = function() end, every = function() return 1 end }
_G._TOS = { fs = F, event = EV }
-- cron refuses to schedule for nobody, so there is somebody.
package.loaded["kernel.users"] = {
  currentSession = function() return { user = "root", tier = 3 } end,
  canAccessAs = function() return true end,
}

local register = require("shell.panels.commands.admin")
local helpers = require("shell.panels.helpers")
helpers.requireRoomy = function(_, name) return pcall(require, name) end

local cron = require("kernel.cron")
pcall(cron.init, { fs = F, event = EV })

local S = {
  K = {}, E = { push = function() end }, P = {}, F = F, D = {}, U = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local C = {}
assert(pcall(register, C, S, {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end, refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return "" end,
  confirm = function() return true end, confirmTyped = function() return true end,
}))

local function run(...)
  local out = {}
  local ok, err = pcall(C.cron, { ... }, function(t) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n"), ok, err
end

print("=== cron add ===")
local out, ok, err = run("add", "bad", "0", 'print("x")')
test("an interval cron refuses is reported, not a Lua error", ok, err)
test("...with the reason", out:find("positive", 1, true) ~= nil, out)

local before = #cron.list()
out, ok, err = run("add", "shell", "300", "run", "/home/me/backup.lua")
test("a shell line is refused when it is added", ok and out:find("Lua", 1, true) ~= nil, out .. tostring(err))
test("...and is not stored", #cron.list() == before, #cron.list())

out, ok, err = run("add", "tick", "60", 'print("x")')
test("Lua source is accepted", ok and out:find("Added job", 1, true) ~= nil, out .. tostring(err))
test("...and is stored", #cron.list() == before + 1, #cron.list())

out, ok, err = run("add", "file", "60", "/home/me/backup.lua")
test("a path to a script is accepted without being read as Lua",
  ok and out:find("Added job", 1, true) ~= nil, out .. tostring(err))

out = run("add", "300", "print(1)")
test("the interval-first form the manual used to show gets the usage line",
  out:find("add <name> <seconds> <script>", 1, true) ~= nil, out)

out = run("add", "name", "soon", "print(1)")
test("a word for an interval says what is wanted", out:find("<seconds>", 1, true) ~= nil, out)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
