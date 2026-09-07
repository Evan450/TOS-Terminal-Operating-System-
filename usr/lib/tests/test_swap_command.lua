-- ╔═══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `swap` and `optimize swap` are ONE function   ║
-- ║                                                                 ║
-- ║  v1.4.0 folded the `swap` command into `optimize swap` to trim   ║
-- ║  the command list. The operator who then used it disagreed:      ║
-- ║  "the `optimize swap` situation is a bit weird, I'd suggest       ║
-- ║  adding an alternative `swap` command". Both spellings now work.  ║
-- ║                                                                   ║
-- ║  Two names for one operation is exactly how two implementations    ║
-- ║  of a boot-config toggle get born, and then diverge. This drives    ║
-- ║  BOTH real command bodies against the same stubbed swap store and   ║
-- ║  boot config and asserts they produce the same effect — so a fix    ║
-- ║  applied to one and not the other fails here.                       ║
-- ╚════════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_swap_command.lua   (from the TOS-Dev root)

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

package.loaded["computer"]  = { uptime = function() return 0 end,
                                freeMemory = function() return 1e6 end,
                                energy = function() return 400 end,
                                maxEnergy = function() return 500 end,
                                beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }

-- ── The swap store, boot config and tab pager the command talks to ──
local store = { bytes = 2048, max = 8192, count = 3, cleared = 0 }
local swapStore = {
  usage = function() return { bytes = store.bytes, max = store.max, count = store.count } end,
  keys  = function() return { "tab:1", "tab:4" } end,
  clear = function() store.cleared = store.cleared + 1; store.bytes = 0; store.count = 0 end,
}

local bootCfg = { advanced = {} }
local saves = 0
package.loaded["kernel.bootcfg"] = {
  load = function() return bootCfg end,
  save = function(_, cfg) saves = saves + 1; bootCfg = cfg; return true end,
  FEATURES = { "swap" },
  _normalize = function(t) return t end,
}
local swept = 0
package.loaded["shell.panels.tabs"] = {
  sweepCold  = function() swept = swept + 1; return 2 end,
  pagedStats = function() return 2, 140 end,
  isPaged    = function() return false end,
}
package.loaded["kernel.screen"] = {
  bufferMode  = function() return "auto" end,
  bufferStats = function() return { total = 0, skipped = 0, ratio = 0 } end,
  setBuffer   = function() return true end,
}

_G._TOS = { fs = {} }

local okA, register = pcall(require, "shell.panels.commands.admin")
if not okA or type(register) ~= "function" then
  print("FAIL: could not load shell/panels/commands/admin.lua: " .. tostring(register))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local S = {
  K = {
    getSwap   = function() return swapStore end,
    getConfig = function() return { get = function() return 25 end,
                                    set = function() end, save = function() return true end } end,
    uptime    = function() return 0 end,
  },
  E = { push = function() end }, P = {}, F = {}, D = {}, U = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return "" end,
  confirm = function() return true end, confirmTyped = function() return true end,
}

local C = {}
local okR, rerr = pcall(register, C, S, deps)
test("admin.lua registers its commands", okR)
if not okR then print("  registration error: " .. tostring(rerr))
  print("*** TESTS FAILED ***"); os.exit(1) end

print("=== `swap` / `optimize swap` Tests ===\n")

local function run(fn, ...)
  local buf = {}
  local ok, err = pcall(fn, { ... }, function(t, c) buf[#buf + 1] = { tostring(t), c } end)
  if not ok then return nil, err end
  local text = {}
  for _, l in ipairs(buf) do text[#text + 1] = l[1] end
  return table.concat(text, "\n")
end

-- ── Both names exist and dispatch ───────────────────────────────────
test("C.swap exists again", type(C.swap) == "function")
test("C.optimize still exists", type(C.optimize) == "function")

-- ── Status: identical output from both spellings ────────────────────
do
  local a = run(C.swap)
  local b = run(C.optimize, "swap")
  test("`swap` produces a status report",
    a ~= nil and a:find("Disk Swap", 1, true) ~= nil)
  eq("`swap` and `optimize swap` print the SAME thing", a, b)
  -- 2048 / 8192 bytes through helpers.fmtSz, and the percentage.
  test("the report names the live usage (2K / 8K, 25%)",
    a:find("2K / 8K", 1, true) ~= nil and a:find("25%%") ~= nil)
  test("the report names the entry count", a:find("Entries: 3", 1, true) ~= nil)
  -- Swap costs disk writes, and OC bills disk I/O per kilobyte. The
  -- report says so rather than letting `optimize power` and `swap` each
  -- claim to be the saving.
  test("the report is honest that paging costs energy",
    a:find("optimize power", 1, true) ~= nil)
end

-- ── keys ────────────────────────────────────────────────────────────
do
  local a = run(C.swap, "keys")
  local b = run(C.optimize, "swap", "keys")
  eq("`swap keys` == `optimize swap keys`", a, b)
  test("...and lists the keys", a:find("tab:1", 1, true) ~= nil)
end

-- ── now: forces a cold sweep through the real tabs module ───────────
do
  swept = 0
  local a = run(C.swap, "now")
  eq("`swap now` swept once", 1, swept)
  test("...and reported it", a:find("Paged out 2", 1, true) ~= nil)
  local b = run(C.optimize, "swap", "now")
  eq("`optimize swap now` swept again", 2, swept)
  eq("same report", a, b)
end

-- ── clear: the destructive one, through both names ──────────────────
do
  store.bytes, store.count, store.cleared = 4096, 5, 0
  run(C.swap, "clear")
  eq("`swap clear` wiped the store", 1, store.cleared)
  store.bytes, store.count = 4096, 5
  run(C.optimize, "swap", "clear")
  eq("`optimize swap clear` wiped it too", 2, store.cleared)
end

-- ── The boot toggle really writes boot.cfg, from both names ─────────
do
  saves = 0; bootCfg = { advanced = {} }
  local a = run(C.swap, "on")
  eq("`swap on` saved boot.cfg", 1, saves)
  eq("...setting the swap feature true", true, bootCfg.advanced.swap)
  test("...and said it needs a reboot", a:find("next boot", 1, true) ~= nil)

  run(C.optimize, "swap", "off")
  eq("`optimize swap off` saved too", 2, saves)
  eq("...setting it false", false, bootCfg.advanced.swap)

  run(C.swap, "auto")
  eq("`swap auto` clears the override", nil, bootCfg.advanced.swap)
  eq("...and saved", 3, saves)
end

-- ── A bad subcommand is refused, not silently treated as status ─────
do
  saves = 0
  local a = run(C.swap, "banana")
  test("`swap banana` is refused", a:find("swap <", 1, true) ~= nil)
  eq("...and wrote nothing", 0, saves)
  -- The usage line must name the spelling the operator typed, not the
  -- other one — that was the original complaint about this command.
  test("`swap`'s usage does not tell them to type `optimize`",
    a:find("optimize swap <", 1, true) == nil)
end

-- ── `optimize` show mentions all three, not just swap ───────────────
do
  local a = run(C.optimize)
  test("optimize show lists disk swap", a:find("Disk swap", 1, true) ~= nil)
  test("optimize show lists the display buffer", a:find("Display buffer", 1, true) ~= nil)
  test("optimize show lists power", a:find("Power", 1, true) ~= nil)
  test("optimize show points at the bare `swap` command",
    a:find("\nswap [", 1, true) ~= nil)
end

-- ── `optimize power` reports without needing a tablet ───────────────
do
  local a = run(C.optimize, "power")
  test("optimize power reports", a ~= nil and a:find("=== Power ===", 1, true) ~= nil)
  test("...naming the active profile", a:find("Profile", 1, true) ~= nil)
  test("...and the machine's stored energy (not just tablets)",
    a:find("Stored", 1, true) ~= nil)
  local b = run(C.optimize, "power", "save")
  test("optimize power save applies", b:find("Power profile: save", 1, true) ~= nil)
  eq("...and published the shell's blank timeout",
    require("kernel.power").PROFILES.save.blankSec, _G._TOS.screenBlankSec)
  local c = run(C.optimize, "power", "turbo")
  test("an unknown profile is refused, with the list",
    c:find("balanced", 1, true) ~= nil)
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
