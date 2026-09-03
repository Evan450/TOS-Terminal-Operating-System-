-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: `why` explainer (helpers, pure)          ║
-- ║                                                            ║
-- ║  whyExplain turns a tier requirement + the caller's tier   ║
-- ║  into operator-readable lines ({text, tone}); the `why`    ║
-- ║  command renders them. tierName maps 0..3 -> GUEST..ROOT.  ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_why.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local helpers = require("shell.panels.helpers")

print("=== `why` explainer Tests ===\n")

-- ── tierName ────────────────────────────────────────────────────────
test("tierName 0 = GUEST", helpers.tierName(0) == "GUEST")
test("tierName 1 = USER",  helpers.tierName(1) == "USER")
test("tierName 2 = ADMIN", helpers.tierName(2) == "ADMIN")
test("tierName 3 = ROOT",  helpers.tierName(3) == "ROOT")

-- ── unknown command ─────────────────────────────────────────────────
local u = helpers.whyExplain("flarp", 0, 1, false)
test("unknown -> first line err tone", u[1] and u[1].tone == "err")
test("unknown -> names the command", u[1].text:find("flarp", 1, true) ~= nil)

-- ── allowed (have >= need) ──────────────────────────────────────────
local ok = helpers.whyExplain("ls", 0, 1, true)
local hasOk = false
for _, l in ipairs(ok) do if l.tone == "ok" then hasOk = true end end
test("allowed -> has an 'ok' line", hasOk)
test("allowed -> title names both tiers", ok[1].text:find("GUEST", 1, true) ~= nil
  and ok[1].text:find("USER", 1, true) ~= nil)

-- ── admin needed, caller is USER ────────────────────────────────────
local a = helpers.whyExplain("flash", 2, 1, true)
local hasErr, hasFix = false, false
for _, l in ipairs(a) do
  if l.tone == "err" then hasErr = true end
  if l.tone == "fix" then hasFix = true end
end
test("denied admin -> has err + fix lines", hasErr and hasFix)
test("denied admin -> title says ADMIN + USER",
  a[1].text:find("ADMIN", 1, true) ~= nil and a[1].text:find("USER", 1, true) ~= nil)

-- ── root needed ─────────────────────────────────────────────────────
local r = helpers.whyExplain("flash", 3, 2, true)
local mentionsRoot = false
for _, l in ipairs(r) do if l.text:find("ROOT", 1, true) then mentionsRoot = true end end
test("denied root -> mentions ROOT", mentionsRoot)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
