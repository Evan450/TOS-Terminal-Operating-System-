-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the executor enforces the registry's tier     ║
-- ║                                                                ║
-- ║  Every command declares a tier in commands.lua's REGISTRY, and  ║
-- ║  until the Sep 2026 pentest only `help` ever read it. A command ║
-- ║  whose body had no adminOnly/rootOnly of its own ran for anyone:║
-- ║  a GUEST, or a first-boot restricted token, could `drive read`  ║
-- ║  raw sectors (under every ACL on a TBFS volume), `redstone set`,║
-- ║  drive a robot, run a tape. The executor now refuses anything   ║
-- ║  below its declared tier, resolving the tier through the seat   ║
-- ║  token exactly as helpers.liveTier does.                        ║
-- ║                                                                ║
-- ║  Drives the REAL executor against the REAL registry.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_dispatch_tier.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

_G._TOS = _G._TOS or {}
package.path = "tos/?.lua;" .. package.path
local ran = {}

-- helpers: the executor's collaborators, with liveTier/fail/tierName shaped
-- exactly like the real ones (seat token -> session tier; nothing -> 0).
package.loaded["shell.panels.helpers"] = {
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
  liveTier = function(St)
    if St and St.U and St.st then
      local s = St.U.getSession(St.st)
      if s and type(s.tier) == "number" then return s.tier end
      return 0
    end
    return (St and St.userTier) or 0
  end,
  tierName = function(n) return ({ [0] = "GUEST", "USER", "ADMIN", "ROOT" })[n] or ("tier " .. n) end,
  fail = function(St, msg, o) o(msg, "ERR"); St.lastFailure = { text = msg }; return false end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.pkg"] = {
  getCommand = function(name)
    if name == "fakegame" then return function() ran.fakegame = true end end
  end,
  getCommandScreen = function() return nil end,
}

local cmds = require("shell.panels.commands")
test("the registry is the real one (drive is tier 1)", (cmds.entry("drive") or {}).tier == 1)

local executorMod = require("shell.panels.executor")

local function cmd(name) return function() ran[name] = true end end
local sessions = {
  g = { user = "guest", tier = 0 }, u = { user = "alice", tier = 1 },
  a = { user = "adam",  tier = 2 }, r = { user = "root",  tier = 3 },
}
local S = {
  W = 80, H = 25, T = { error = "ERR" }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end },
  D = {},
  U = { getSession = function(tok) return sessions[tok] end },
}
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return {} end,
  C = { drive = cmd("drive"), ls = cmd("ls"), useradd = cmd("useradd"),
        flash = cmd("flash"), rs = cmd("rs"), hello = cmd("hello") },
})

local function tryAs(tok, line, name)
  ran = {}; S.st = tok; S.lastDenial = nil
  exec(line)
  return ran[name] == true
end

print("=== executor enforces registry tiers ===")
print()
test("GUEST cannot run a tier-1 command (drive read)", not tryAs("g", "drive read abcd 1", "drive"))
test("...and the denial is recorded for `why`",
  S.lastDenial and S.lastDenial.cmd == "drive" and S.lastDenial.need == 1 and S.lastDenial.have == 0)
test("...with an E-403 message", S.lastFailure and tostring(S.lastFailure.text):find("E-403", 1, true) ~= nil)
test("GUEST cannot reach a tier-1 command by its alias (rs)", not tryAs("g", "rs set left 15", "rs"))
test("GUEST still runs a tier-0 command (ls)", tryAs("g", "ls", "ls"))
test("GUEST still runs an unregistered built-in", tryAs("g", "hello", "hello"))
test("GUEST still runs a package command (sandboxed; not in the registry)",
  tryAs("g", "fakegame", "fakegame"))
test("USER runs a tier-1 command", tryAs("u", "drive list", "drive"))
test("USER cannot run a tier-2 command (useradd)", not tryAs("u", "useradd bob", "useradd"))
test("ADMIN runs a tier-2 command", tryAs("a", "useradd bob", "useradd"))
test("ADMIN cannot run a tier-3 command (flash)", not tryAs("a", "flash bios.lua", "flash"))
test("ROOT runs a tier-3 command", tryAs("r", "flash bios.lua", "flash"))
test("an expired seat token drops to GUEST", not tryAs("gone", "drive list", "drive"))
-- sudo swaps the seat token for an elevated one; the gate must see it.
sessions.elev = { user = "alice", tier = 2, elevated = true }
test("an elevated (sudo) token counts at its elevated tier", tryAs("elev", "useradd carol", "useradd"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
