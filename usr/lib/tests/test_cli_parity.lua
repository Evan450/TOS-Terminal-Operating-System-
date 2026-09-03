-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: the CLI has the TUI's commands           ║
-- ║                                                            ║
-- ║  The CLI used to be a SECOND hand-rolled command table —   ║
-- ║  85 commands against the panels shell's 124, with the 45   ║
-- ║  missing ones discovered one at a time by operators. It    ║
-- ║  now dispatches through the same registry, and this file   ║
-- ║  is what keeps it that way: the parity is asserted from    ║
-- ║  the registry itself, so a command added tomorrow is       ║
-- ║  covered without anyone remembering to update a list.      ║
-- ║                                                            ║
-- ║  It also pins the deps contract. shell/cli.lua has to      ║
-- ║  supply every dep the category files reach for; miss one   ║
-- ║  and the failure is a nil call deep inside a command, on   ║
-- ║  a box where the operator went to the CLI because          ║
-- ║  something was already wrong.                              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cli_parity.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end

package.loaded["computer"] = {
  uptime = function() return 0 end,
  pullSignal = function() return nil end,
  freeMemory = function() return 200000 end,
  totalMemory = function() return 400000 end,
  getDeviceInfo = function() return {} end,
}
package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end,
  methods = function() return {} end,
}
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local Cmds = require("shell.panels.commands")

print("=== CLI parity Tests ===")
print()

-- ══════════════════════════════════════════════════════════════════════
-- The CLI file exists and is a launcher-shaped module
-- ══════════════════════════════════════════════════════════════════════
local cli = require("shell.cli")
test("shell.cli loads", "table", type(cli))
test("and exposes run()", "function", type(cli.run))

-- The old CLI lived inside shell/init.lua. That file is now a launcher,
-- and it must stay one: if it grows a command table again, the drift
-- this whole change removed is back.
do
  local h = io.open("tos/shell/init.lua", "rb")
  local src = h and h:read("*a") or ""
  if h then h:close() end
  local lines = select(2, src:gsub("\n", "\n"))
  ok("shell/init.lua is a launcher, not a shell (< 200 lines)", lines < 200)
  -- A handful of `C.<name> = function` assignments is how the old one
  -- was built. None should remain.
  local assigns = 0
  for _ in src:gmatch("C%.%w+%s*=%s*function") do assigns = assigns + 1 end
  test("no command bodies left in the launcher", 0, assigns)
  ok("it hands off to shell.cli", src:find("shell.cli", 1, true) ~= nil)
end

-- ══════════════════════════════════════════════════════════════════════
-- The two shells are reachable from each other
-- ══════════════════════════════════════════════════════════════════════
do
  ok("`cli` is a registry command", Cmds.entry("cli") ~= nil)
  ok("`tui` is a registry command", Cmds.entry("tui") ~= nil)
  -- Tier 0 on purpose: which interface you use is not a privilege, and
  -- the CLI is specifically what you want reachable when the full one is
  -- misbehaving.
  test("`cli` is available to every tier", 0, Cmds.entry("cli").tier)
  test("`tui` is available to every tier", 0, Cmds.entry("tui").tier)
  ok("both live in core (always loaded first)",
    Cmds.entry("cli").category == "core" and Cmds.entry("tui").category == "core")
end

-- ══════════════════════════════════════════════════════════════════════
-- Parity, asserted from the registry
-- ══════════════════════════════════════════════════════════════════════
-- A fake shell state and the full dep set, exactly as shell/cli.lua
-- builds them. If the CLI can resolve every registered name through
-- M.build, then it can run every command the TUI can — that IS the
-- parity claim, and it is checked against the registry rather than a
-- list somebody has to maintain.
local function fakeTheme()
  return setmetatable({}, { __index = function() return 0xFFFFFF end })
end
local S = {
  F = { exists = function() return false end, list = function() return {} end,
        isDirectory = function() return false end, join = function(...) return table.concat({...}, "/") end,
        normalize = function(p) return p end, readFile = function() return nil end,
        writeFile = function() return true end },
  D = { getTheme = fakeTheme, getGpuTier = function() return 2 end,
        getSize = function() return 80, 25 end, getGpu = function() return nil end,
        c = function() return 0xFFFFFF end, set = function() end,
        fill = function() end, clear = function() end },
  T = fakeTheme(),
  U = nil, K = nil, E = nil, P = nil, SC = nil, NM = nil,
  W = 80, H = 25, cwd = "/", who = "root", userTier = 3, tier = 2,
  tabs = {}, browser = { path = "/", sel = 1, scroll = 0, files = {} },
  cmdHistory = {}, isCLI = true,
}
local noop = function() end
local deps = {
  rp = function(p) return p end,
  canRead = function() return true end,
  canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end,
  adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  refreshBrowser = noop, loadFiles = noop, tabs = S.tabs,
  pullSignal = function() return nil end,
  openViewTab = noop, openLiveTab = noop, openEditTab = noop, createTab = noop,
  promptInput = function() return nil end,
  alert = noop, confirm = function() return false end, dialog = function() return 2 end,
  drawAll = noop, drawOutRow = noop,
}

local C = Cmds.build(S, deps)

do
  local names = Cmds.commandNames()
  ok("the registry has a substantial command set", #names >= 100)
  local missing = {}
  for _, name in ipairs(names) do
    if type(C[name]) ~= "function" then missing[#missing + 1] = name end
  end
  if #missing > 0 then
    print("      unreachable from the CLI: " .. table.concat(missing, " "))
  end
  test("every registered command resolves through the CLI's table", 0, #missing)
end

-- The 45 that were genuinely absent from the old hand-rolled CLI. Named
-- explicitly rather than left to the loop above, because these are the
-- ones an operator actually hit — a regression here should say WHICH.
do
  local WERE_MISSING = {
    "alias", "audio", "backup", "battery", "bootsettings", "colors", "config",
    "crash", "date", "desktop", "devices", "diag", "doctor", "drive", "flash",
    "hardware", "hostname", "install", "intercom", "internet", "jbod",
    "keychain", "kiosk", "lang", "menu", "monitor", "net", "notify",
    "optimize", "ping", "profile", "rbmk", "screendump", "settings", "srm",
    "sudo", "swap", "tail", "tape", "theme", "time", "top", "tree",
    "unalias", "uninstall", "vault", "ver", "watch", "which", "why",
  }
  local stillMissing = {}
  for _, name in ipairs(WERE_MISSING) do
    -- `swap` was folded into `optimize` in v1.4.0 and is legitimately
    -- gone from the registry; skip anything the registry no longer
    -- claims rather than asserting a command back into existence.
    if Cmds.entry(name) and type(C[name]) ~= "function" then
      stillMissing[#stillMissing + 1] = name
    end
  end
  if #stillMissing > 0 then
    print("      still missing: " .. table.concat(stillMissing, " "))
  end
  test("the commands the old CLI lacked are all reachable now", 0, #stillMissing)
end

-- ══════════════════════════════════════════════════════════════════════
-- Lazy loading — the other half of the operator's ask
-- ══════════════════════════════════════════════════════════════════════
-- "As capable as the TUI, just more lazy-loaded." Capability is above;
-- this is the laziness. A session that only touches core commands must
-- not have parsed admin.lua or extras.lua — the CLI is what a low-RAM
-- box falls back to and what `ui=cli` boots into.
do
  for _, m in ipairs({ "shell.panels.commands.core",
                       "shell.panels.commands.admin",
                       "shell.panels.commands.extras" }) do
    package.loaded[m] = nil
  end
  local C2 = Cmds.build(S, deps)
  local _ = C2.ls          -- a core command
  ok("touching a core command loads core", package.loaded["shell.panels.commands.core"] ~= nil)
  test("...and NOT admin", nil, package.loaded["shell.panels.commands.admin"])
  test("...and NOT extras", nil, package.loaded["shell.panels.commands.extras"])
  local _ = C2.flash       -- an admin command
  ok("touching an admin command loads admin", package.loaded["shell.panels.commands.admin"] ~= nil)
  test("...and still not extras", nil, package.loaded["shell.panels.commands.extras"])
end

-- ══════════════════════════════════════════════════════════════════════
-- The dep contract
-- ══════════════════════════════════════════════════════════════════════
-- Every `deps.foo` the category files reach for must be something
-- shell/cli.lua actually supplies. A missing one is a nil call deep
-- inside a command, on a box where the operator came to the CLI
-- *because* something was already wrong.
do
  local needed = {}
  for _, cat in ipairs({ "core", "admin", "extras" }) do
    local h = io.open("tos/shell/panels/commands/" .. cat .. ".lua", "rb")
    local src = h and h:read("*a") or ""
    if h then h:close() end
    for name in src:gmatch("deps%.([a-zA-Z_]+)") do needed[name] = true end
  end
  local h = io.open("tos/shell/cli.lua", "rb")
  local cliSrc = h and h:read("*a") or ""
  if h then h:close() end
  local absent = {}
  for name in pairs(needed) do
    -- `C` is set on deps after build, not inside the deps literal.
    if name ~= "C" and not cliSrc:find(name, 1, true) then
      absent[#absent + 1] = name
    end
  end
  table.sort(absent)
  if #absent > 0 then
    print("      deps the CLI never supplies: " .. table.concat(absent, " "))
  end
  test("the CLI supplies every dep the commands use", 0, #absent)
end

-- ══════════════════════════════════════════════════════════════════════
-- Layering: the CLI may lean on the registry, the floor may not
-- ══════════════════════════════════════════════════════════════════════
do
  -- Three layers, each the fallback for the one above:
  --   panels TUI → CLI → emergency terminal.
  -- The emergency terminal lives in kernel/init.lua and must keep
  -- depending on NOTHING the other two need, or the layer below the
  -- failure shares the failure.
  local h = io.open("tos/kernel/init.lua", "rb")
  local src = h and h:read("*a") or ""
  if h then h:close() end
  -- Bounded by the next top-level comment banner rather than by `\nend\n`
  -- — the function's own nested blocks end at column 0 too.
  local emerg = src:match("function kernel%.emergencyShell%(%)(.-)\n%-%- =====")
  ok("the emergency shell is still there", emerg ~= nil and #emerg > 0)
  if emerg then
    test("it does not require the command registry", nil,
      emerg:find("shell.panels.commands", 1, true))
    test("it does not require the CLI", nil, emerg:find("shell.cli", 1, true))
    test("it does not require the panels TUI", nil, emerg:find("shell.panels", 1, true))
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- The quit menu says the same thing in both places
-- ══════════════════════════════════════════════════════════════════════
do
  -- The prompt is drawn from two files (^Q in events.lua, the menu
  -- action in menus.lua). Two spellings of the same four choices is how
  -- an operator learns to distrust both.
  local function readf(p)
    local h = io.open(p, "rb"); local s = h and h:read("*a") or ""; if h then h:close() end; return s
  end
  local ev = readf("tos/shell/panels/events.lua")
  local mn = readf("tos/shell/panels/menus.lua")
  local PROMPT = "[1]Reboot [2]Shut down [3]Log out [4]CLI Mode [^Q]Cancel"
  ok("the ^Q quit prompt offers CLI Mode", ev:find(PROMPT, 1, true) ~= nil)
  ok("the menu quit prompt says exactly the same", mn:find(PROMPT, 1, true) ~= nil)
  ok("the old '[4]Shell' label is gone from events", ev:find("[4]Shell", 1, true) == nil)
  ok("the old '[4]Shell' label is gone from menus", mn:find("[4]Shell", 1, true) == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
