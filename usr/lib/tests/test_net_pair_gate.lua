-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `net pair` is an admin action                 ║
-- ║                                                                ║
-- ║  Pairing installs a shared secret, which the trust manager      ║
-- ║  reserves for ADMIN -- but chatpair installs it as the kernel,  ║
-- ║  and `net` is a tier-1 command. Every other trust-changing      ║
-- ║  `net` subcommand passes the caller's tier on; `pair` checked   ║
-- ║  nothing, so a plain user could open a pairing window or        ║
-- ║  complete a pair (Sep 2026 pentest).                            ║
-- ║                                                                ║
-- ║  Drives the REAL shell/ext.lua command body with a ctx shaped   ║
-- ║  like the one commands/extras.lua passes it.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_pair_gate.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.loaded["computer"] = { uptime = function() return 100 end }
package.path = "tos/?.lua;" .. package.path
local X = dofile("tos/shell/ext.lua")

local calls = {}
local CP = {
  startWindow = function() calls[#calls + 1] = "startWindow"; return "ABCD", 160 end,
  connect     = function() calls[#calls + 1] = "connect"; return true end,
  windowInfo  = function() calls[#calls + 1] = "windowInfo"; return nil end,
}
local NM = { getChatPair = function() return CP end }
local sessions = { u = { user = "alice", tier = 1 }, a = { user = "adam", tier = 2 } }
local function run(tok, args)
  calls = {}
  local out = {}
  X.net(args, {
    K  = { getNet = function() return NM end },
    U  = { getSession = function(t) return sessions[t] end },
    st = tok,
    o  = function(line) out[#out + 1] = tostring(line) end,
  })
  return out
end

print("=== net pair is admin-only ===")
print()
run("u", { "pair", "start" })
test("a USER cannot open a pairing window", #calls == 0)
run("u", { "pair", "0123abcd", "WXYZ" })
test("a USER cannot complete a pair", #calls == 0)
run("u", { "pair", "status" })
test("a USER may still ask for the pairing status", calls[1] == "windowInfo")
run("a", { "pair", "start" })
test("an ADMIN opens a pairing window", calls[1] == "startWindow")
run("a", { "pair", "0123abcd", "WXYZ" })
test("an ADMIN completes a pair", calls[1] == "connect")
run(nil, { "pair", "start" })
test("no session at all cannot pair", #calls == 0)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
