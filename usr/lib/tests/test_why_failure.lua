-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `why` explains failures, not just denials    ║
-- ║                                                                ║
-- ║  Operator report (emulator, GitHub build): "I tried deleting    ║
-- ║  the TOS folder again and it correctly stopped me ... but when  ║
-- ║  I tried using the why command on it it just showed its usage." ║
-- ║                                                                 ║
-- ║  `why` only knew about TIER denials (S.lastDenial, written by   ║
-- ║  rootOnly/adminOnly). The protected-path guard is not a tier     ║
-- ║  check, so the single most likely refusal was the one `why`      ║
-- ║  could not discuss.                                              ║
-- ║                                                                  ║
-- ║  THE SEAM: explainFailure matches messages by substring, and     ║
-- ║  those messages are defined in OTHER files. A substring match     ║
-- ║  across a file boundary rots in silence, so this test builds      ║
-- ║  each message from the module that really produces it — securefs  ║
-- ║  for the protected-path refusal, helpers for the permission and   ║
-- ║  tier ones — instead of pasting a copy here.                      ║
-- ╚═══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_why_failure.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1024 * 1024 end }
package.loaded["component"] = { list = function() return function() return nil end end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local helpers = require("shell.panels.helpers")

local here = (arg and arg[0]) or "usr/lib/tests/test_why_failure.lua"
local base = here:gsub("[^/\\]*$", "")
local securefs
for _, p in ipairs({ base .. "../../../tos/kernel/securefs.lua",
    "tos/kernel/securefs.lua", "TOS-Dev/tos/kernel/securefs.lua" }) do
  local chunk = loadfile(p); if chunk then securefs = chunk(); break end
end

print("=== `why` failure-explainer Tests ===\n")

-- ── The real protected-path refusal, from the module that writes it ──
if not (securefs and securefs._protectedMsg) then
  test("securefs exposes _protectedMsg for this test", false)
else
  -- Exactly what an operator sees after `rm -r /tos` (the reported case).
  local msg = securefs._protectedMsg("removing", "/tos", nil)
  test("securefs really produces a message", type(msg) == "string" and #msg > 40)
  local lines = helpers.explainFailure(msg)
  test("explainFailure recognises the protected-path refusal", lines ~= nil)
  if lines then
    local text = ""
    for _, l in ipairs(lines) do text = text .. l.text .. "\n" end
    test("...and names the escape hatch (`protect off`)",
      text:find("protect off", 1, true) ~= nil)
    test("...and says it is a guard, not a permission problem",
      text:lower():find("guard", 1, true) ~= nil)
    local hasErr, hasFix = false, false
    for _, l in ipairs(lines) do
      if l.tone == "err" then hasErr = true end
      if l.tone == "fix" then hasFix = true end
    end
    test("...with both an err line and a fix line", hasErr and hasFix)
  end

  -- The root-session variant is a DIFFERENT string (it offers `protect
  -- off` as something the caller can actually do). Both must be known.
  local usersMod = { TIER = { ROOT = 3 } }
  package.loaded["kernel.users"] = usersMod
  local msgRoot = securefs._protectedMsg("writing to", "/etc", { tier = 3 })
  test("root variant is also recognised", helpers.explainFailure(msgRoot) ~= nil)
end

-- ── The shell's own permission refusal, from helpers.fail ────────────
-- helpers.canAccess writes this; drive helpers.fail directly so the test
-- does not need a users module wired up.
do
  local S = { T = { error = 0xFF0000 }, curCmd = "cat" }
  helpers.fail(S, "Permission denied: not readable by you")
  test("helpers.fail records the message for `why`",
    S.lastFailure ~= nil and S.lastFailure.text:find("Permission denied", 1, true) ~= nil)
  test("helpers.fail names the command", S.lastFailure.cmd == "cat")
  test("helpers.fail still shows it on the status row",
    type(S.lastOut) == "table" and S.lastOut[1]:find("Permission denied", 1, true) ~= nil)
  test("the permission refusal is explained",
    helpers.explainFailure(S.lastFailure.text) ~= nil)
end

-- ── The tier gates record BOTH, and `why` prefers the tier one ───────
do
  local S = { T = { error = 0xFF0000 }, curCmd = "flash", userTier = 1 }
  local allowed = helpers.rootOnly(S)
  test("rootOnly still denies", allowed == false)
  test("rootOnly records lastDenial (tier numbers for whyExplain)",
    S.lastDenial ~= nil and S.lastDenial.need == 3)
  test("rootOnly ALSO records lastFailure (generic path)",
    S.lastFailure ~= nil and S.lastFailure.cmd == "flash")
end

-- ── noteFailure keeps the FIRST error of a run ───────────────────────
do
  local S = {}
  helpers.noteFailure(S, "rm", "Not trashed: file too large for trash (9000 > 4096)")
  helpers.noteFailure(S, "rm", "It is still there. Delete it for good with: rm --hard x")
  test("first error wins, not the trailing advice",
    S.lastFailure.text:find("Not trashed", 1, true) ~= nil)
  helpers.clearFailure(S)
  test("clearFailure forgets it", S.lastFailure == nil and S.lastDenial == nil)
  helpers.noteFailure(S, "rm", "")
  test("an empty message records nothing", S.lastFailure == nil)
end

-- ── Every FAILURES key is reachable, and unknown text stays unknown ──
do
  test("trash refusal explained", helpers.explainFailure(
    "Not trashed: file too large for trash (9000 > 4096)") ~= nil)
  test("rm -r guard explained", helpers.explainFailure(
    "Refusing to remove protected path without -r: /tos") ~= nil)
  test("directory-without-r explained", helpers.explainFailure(
    "Cannot remove directory without -r: /home/x") ~= nil)
  test("unknown command explained", helpers.explainFailure(
    "Unknown command: flarp") ~= nil)
  test("OOM explained", helpers.explainFailure(
    "tos/shell/x.lua:1: not enough memory") ~= nil)
  test("category-load failure explained", helpers.explainFailure(
    "'reboot' could not be loaded.") ~= nil)
  --! The honest half: `why` must NOT invent an explanation. An
  --! unrecognised message returns nil so the command says so and points
  --! at `log`, rather than confidently guessing.
  test("an unrecognised message returns nil", helpers.explainFailure(
    "the flux capacitor is at 41%") == nil)
  test("a non-string returns nil", helpers.explainFailure(nil) == nil)
end

-- ── Ordering: the protected message must not be caught by a looser key ─
-- protectedMsg contains "protected system path" AND the word "removing";
-- if a broader entry were checked first the operator would get the wrong
-- advice, which is worse than none.
do
  local msg = "Refused: removing /tos is a protected system path. This guard "
    .. "sits above the permission model."
  local lines = helpers.explainFailure(msg)
  local text = ""
  for _, l in ipairs(lines or {}) do text = text .. l.text .. "\n" end
  test("protected-path message is not explained as a plain ACL denial",
    text:find("protect off", 1, true) ~= nil)
end

-- ── THE COMMAND ITSELF, end to end ──────────────────────────────────
-- The helper being right is not what the operator reported. `why` is,
-- so drive the REAL C.why out of core.lua against a shell state holding
-- a real refusal and check what it prints.
do
  local okC, register = pcall(require, "shell.panels.commands.core")
  if not okC or type(register) ~= "function" then
    test("core.lua loads (for the `why` command itself)", false)
    print("  load error: " .. tostring(register))
  else
    local S = {
      K = { uptime = function() return 0 end }, E = { push = function() end },
      P = {}, F = {}, D = {}, U = nil,
      T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
      tier = 1, userTier = 1, W = 80, H = 25, cwd = "/", displayIdx = 1,
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
    local okR = pcall(register, C, S, deps)
    test("core.lua registers", okR and type(C.why) == "function")

    local function whyOut(args)
      local buf = {}
      local ok = pcall(C.why, args, function(t) buf[#buf + 1] = tostring(t) end)
      return ok and table.concat(buf, "\n") or nil
    end

    -- 1. Nothing has failed: `why` says so, and still offers the usage.
    local idle = whyOut({})
    test("`why` with nothing to explain says so",
      idle and idle:find("Nothing has failed", 1, true) ~= nil)
    test("...and still shows how to use it",
      idle and idle:find("why <command>", 1, true) ~= nil)

    -- 2. THE REPORTED CASE: a protected-path refusal, then `why`.
    local refusal = (securefs and securefs._protectedMsg
      and securefs._protectedMsg("removing", "/tos", nil))
      or "Refused: removing /tos is a protected system path."
    helpers.noteFailure(S, "rm", refusal)
    local out = whyOut({})
    test("`why` after a protected-path refusal is NOT the usage line",
      out ~= nil and out:find("why <command>", 1, true) == nil)
    test("...it names the command that failed", out:find("rm failed", 1, true) ~= nil)
    test("...quotes the refusal back", out:find("protected system path", 1, true) ~= nil)
    test("...and explains it", out:find("protect off", 1, true) ~= nil)

    -- 3. A failure with no canned explanation: admit it, don't invent one.
    helpers.clearFailure(S)
    helpers.noteFailure(S, "frobnicate", "the flux capacitor is at 41%")
    local odd = whyOut({})
    test("an unexplained failure is still quoted back",
      odd:find("flux capacitor", 1, true) ~= nil)
    test("...and `why` admits it has no explanation",
      odd:find("No canned explanation", 1, true) ~= nil)
    test("...pointing at the log rather than guessing",
      odd:find("log", 1, true) ~= nil)

    -- 4. A tier denial still takes precedence (the original behaviour).
    S.lastDenial = { cmd = "flash", need = 3, have = 1 }
    local tierOut = whyOut({})
    test("a tier denial is still explained as a tier denial",
      tierOut:find("ROOT", 1, true) ~= nil and tierOut:find("flash", 1, true) ~= nil)

    -- 5. `why <command>` is untouched.
    local named = whyOut({ "ls" })
    test("`why <command>` still works", named:find("ls", 1, true) ~= nil)
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
