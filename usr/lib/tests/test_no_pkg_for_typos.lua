-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a typo does not load the package manager on  ║
-- ║  a machine that has no packages                                ║
-- ║                                                                ║
-- ║  Every unknown command asked kernel.pkg whether a package      ║
-- ║  provides it, and so did every /usr/bin program, the Home      ║
-- ║  launcher and the mouse driver. On the headless machine the    ║
-- ║  first typo of a session left the package manager resident:    ║
-- ║  about 116 KB at 2 MB, and at 1 MB free memory fell from 63 KB ║
-- ║  to 22 KB. A machine with no packages -- every fresh install,  ║
-- ║  every machine at the memory floor -- has nothing to find.     ║
-- ║  helpers.mayHavePackages answers from one directory listing.   ║
-- ║  Drives the real helper and the real executor.                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_no_pkg_for_typos.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { freeMemory = function() return 1e6 end, totalMemory = function() return 2097152 end,
  uptime = function() return 0 end }
package.loaded["component"] = { list = function() return function() end end }

-- The kernel's fs, as the shell reaches it through _TOS.
local files = {}
local kfs = {
  exists = function(p)
    if files[p] then return true end
    for k in pairs(files) do if k:sub(1, #p + 1) == p .. "/" then return true end end
    return false
  end,
  list = function(p)
    local out, seen = {}, {}
    for k in pairs(files) do
      local rest = k:sub(1, #p + 1) == p .. "/" and k:sub(#p + 2)
      local head = rest and rest:match("^([^/]+)")
      if head and not seen[head] then seen[head] = true; out[#out + 1] = head .. "/" end
    end
    return out
  end,
}
_G._TOS = { fs = kfs }

local helpers = dofile("tos/shell/panels/helpers.lua")
local may = helpers.mayHavePackages

print("=== a typo does not load the package manager ===")
print()

-- ── The question, alone ────────────────────────────────────────────
package.loaded["kernel.pkg"] = nil
test("no /var/pkg/installed: no package can be installed", may() == false)
files["/var/pkg/installed/.keep"] = nil
files["/var/pkg/other/x"] = "1"
test("...nor with only other things under /var/pkg", may() == false)
files["/var/pkg/installed/calc/package.lua"] = "return {}"
test("a package directory: maybe", may() == true)
files["/var/pkg/installed/calc/package.lua"] = nil
local realList = kfs.list
kfs.list = function() local done = false return function() if not done then done = true return "calc/" end end end
files["/var/pkg/installed/calc/package.lua"] = "return {}"
test("a listing that is an iterator is read too", may() == true)
kfs.list = realList
files["/var/pkg/installed/calc/package.lua"] = nil
kfs.exists = function() error("disk pulled") end
test("a listing that cannot be read is a maybe, never a no", may() == true)
kfs.exists = function(p) return p == "/var/pkg/installed" end
kfs.list = function() return nil end
test("...and so is a directory that will not list", may() == true)
kfs.list = realList
kfs.exists = function(p)
  if files[p] then return true end
  for k in pairs(files) do if k:sub(1, #p + 1) == p .. "/" then return true end end
  return false
end
_G._TOS = nil
test("no kernel fs to ask: maybe", may() == true)
_G._TOS = { fs = kfs }
package.loaded["kernel.pkg"] = {}
test("already loaded: maybe, without a look (it is paid for)", may() == true)
package.loaded["kernel.pkg"] = nil

-- ── Through the real executor ──────────────────────────────────────
local loads, ran = 0, {}
package.preload["kernel.pkg"] = function()
  loads = loads + 1
  return {
    getCommand = function(name)
      if name == "fakegame" then return function() ran.fakegame = true end end
    end,
    getCommandScreen = function() return nil end,
  }
end
package.loaded["shell.panels.helpers"] = {
  mayHavePackages = may,   -- the real one
  routeOutput = function(n) return n == 0 and "clear" or "inline" end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
  clearFailure = function(St) if St then St.lastFailure = nil end end,
  noteFailure = function(St, cmd, text)
    if St and not St.lastFailure then St.lastFailure = { cmd = cmd, text = text } end
  end,
  liveTier = function() return 3 end,
  tierName = function(n) return "tier " .. n end,
  fail = function(St, msg, o) o(msg, "ERR"); St.lastFailure = { text = msg }; return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
local executorMod = require("shell.panels.executor")
local S = {
  W = 80, H = 25, T = { error = "ERR" }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {}, userTier = 3,
}
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return {} end,
  C = { ls = function() ran.ls = true end },
})

exec("xyzzy")
test("a typo on a machine with no packages does not load kernel.pkg", loads == 0, loads)
test("...and is still reported as an unknown command", S.lastFailure
  and tostring(S.lastFailure.text):find("xyzzy", 1, true) ~= nil, S.lastFailure and S.lastFailure.text)
exec("ls")
test("built-ins run as before", ran.ls == true and loads == 0)

files["/var/pkg/installed/fakegame/package.lua"] = "return {}"
exec("fakegame")
test("with a package installed, its command loads the manager and runs", loads == 1 and ran.fakegame == true, loads)
exec("xyzzy")
test("...and the manager loads once, not per lookup", loads == 1, loads)

-- ── Every other place that asked ───────────────────────────────────
local function src(rel)
  local f = io.open(rel, "rb"); if not f then return "" end
  local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n"))
end
local events = src("tos/shell/panels/events.lua")
test("the 'Running ...' check asks first", events:find("if helpers.mayHavePackages() then\n                    local okP, pkgMod = pcall(require, \"kernel.pkg\")", 1, true) ~= nil)
local executor = src("tos/shell/panels/executor.lua")
local _, nExec = executor:gsub("if helpers.mayHavePackages%(%) then ok[%w]*, pkgMod = pcall%(require, \"kernel.pkg\"%)", "")
test("the executor asks before both of its lookups (commands, /usr/bin caps)", nExec == 2, nExec)
test("the Home launcher asks", src("tos/shell/panels/desktop.lua"):find("H.mayHavePackages()", 1, true) ~= nil)
test("the mouse driver asks", src("tos/shell/panels/mouse.lua"):find("H.mayHavePackages()", 1, true) ~= nil)

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
