-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a tab app typed at the command line says so  ║
-- ║                                                                ║
-- ║  monitor, settings, desktop and chat are full-screen tabs. The ║
-- ║  CLI has one pseudo-tab and draws none, so typed there each    ║
-- ║  made a tab nobody would ever see, printed nothing and gave    ║
-- ║  the prompt back. The local worker found it with `monitor` on  ║
-- ║  the headless machine: "monitor" then "root:/$", against a     ║
-- ║  help line that promises a live monitor.                       ║
-- ║                                                                ║
-- ║  Runs the real core.lua and extras.lua with the apps stubbed,  ║
-- ║  at the command line and in the full interface.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cli_tab_apps.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 10 end,
  totalMemory = function() return 2048 * 1024 end,
  freeMemory = function() return 1024 * 1024 end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local opened = {}
for mod, name in pairs({ ["shell.panels.monitorapp"] = "monitor", ["shell.panels.settingsapp"] = "settings",
                         ["shell.panels.desktop"] = "desktop", ["shell.panels.chatapp"] = "chat" }) do
  package.loaded[mod] = { open = function() opened[name] = true end }
end

local function machine(isCLI)
  local S = {
    T = setmetatable({}, { __index = function(_, k) return k end }),
    F = { exists = function() return false end, join = function(a, b) return a .. "/" .. b end },
    K = {}, E = {}, D = {}, W = 80, H = 25, st = "tok", isCLI = isCLI,
    NM = {},  -- a network, so chat gets as far as its tab
    P = { getForeground = function() return 1 end,
          list = function() return { { pid = 1, name = "shell", state = "running", user = "root" } } end },
    U = { getSession = function() return { user = "root", tier = 3 } end },
    tabs = { { type = "shell", label = "CLI" } },
  }
  local deps = setmetatable({ rp = function(p) return p end }, {
    __index = function() return function() return true end end })
  local C = {}
  assert(loadfile("tos/shell/panels/commands/core.lua"))()(C, S, deps)
  assert(loadfile("tos/shell/panels/commands/extras.lua"))()(C, S, deps)
  return function(name)
    local out = {}
    C[name]({}, function(line) out[#out + 1] = tostring(line) end)
    return table.concat(out, "\n")
  end
end

print("=== at the command line ===")
local cli = machine(true)
for _, name in ipairs({ "monitor", "settings", "desktop", "chat" }) do
  opened = {}
  local out = cli(name)
  test(name .. " says it is a full-screen app", out:find("full-screen app", 1, true) ~= nil, out)
  test(name .. " says how to reach it", out:find("Type 'tui' for the full interface, then '" .. name .. "'", 1, true) ~= nil, out)
  test(name .. " makes no tab nobody will see", not opened[name])
end
local mon = cli("monitor")
test("monitor shows the processes instead", mon:find("PID", 1, true) ~= nil and mon:find("shell", 1, true) ~= nil, mon)
local widest = 0
for line in mon:gmatch("[^\n]+") do widest = math.max(widest, #line) end
test("no line of it is wider than 80 columns", widest <= 80, widest)

print("=== in the full interface ===")
local tui = machine(false)
for _, name in ipairs({ "monitor", "settings", "desktop", "chat" }) do
  opened = {}
  local out = tui(name)
  test(name .. " opens its tab", opened[name] == true, out)
  test(name .. " says nothing about the command line", out:find("full-screen app", 1, true) == nil, out)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
