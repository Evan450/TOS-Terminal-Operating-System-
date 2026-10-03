-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: when the full interface will not start, the  ║
-- ║  command line says why                                         ║
-- ║                                                                ║
-- ║  On the headless machine, with shell/panels/init.lua broken on ║
-- ║  purpose, the seat landed in a working CLI -- as designed --   ║
-- ║  that never said why. The reason was drawn for two seconds at  ║
-- ║  most (any signal ends that wait) and then the CLI's banner    ║
-- ║  replaced it. Typing `tui` failed the same way and showed the  ║
-- ║  same banner again: no message anywhere a person would read.   ║
-- ║                                                                ║
-- ║  Drives the real shell/init.lua mode loop with a stubbed       ║
-- ║  kernel and a CLI that records what it was handed.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_tui_failure_reported.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end,
  totalMemory = function() return 4096 * 1024 end,
  pullSignal = function() return nil end,
}

print("=== a failed full interface is reported at the command line ===")

local function runShell(shape, tuiBroken, cliScript)
  package.loaded["shell.init"] = nil
  package.loaded["kernel.bootcfg"] = { ui = function() return shape, shape end, PANELS_MIN_KB = 1536 }
  package.loaded["shell.panels"] = nil
  package.preload["shell.panels"] = function()
    if tuiBroken then error("broken on purpose", 0) end
    return { run = function() return "cli" end }
  end
  local seen = {}
  package.loaded["shell.cli"] = {
    run = function(ctx)
      seen[#seen + 1] = { tuiFailed = ctx.tuiFailed }
      return cliScript[#seen] or "logout"
    end,
  }
  local D = {
    getSize = function() return 80, 25 end,
    clear = function() end, set = function() end,
    c = function() return 0 end,
  }
  local k = {
    getEvent = function() return {} end, getProc = function() return {} end,
    getSecureFS = function() return { exists = function() return true end } end,
    getDisplay = function() return D end,
    getUsers = function() return { getSession = function() return { user = "root" } end } end,
    getConfig = function() return {} end, getNet = function() return nil end,
  }
  local shell = assert(loadfile("tos/shell/init.lua"))()
  shell.run(k, "tok")
  return seen
end

-- The panels will not load: the CLI it falls back to must be told why.
local seen = runShell("home", true, { "tui", "logout" })
test("the shell fell back to the command line", #seen >= 1)
test("...and handed it the reason",
  seen[1] and type(seen[1].tuiFailed) == "string" and seen[1].tuiFailed:find("broken on purpose", 1, true) ~= nil,
  seen[1] and seen[1].tuiFailed)
test("`tui` failing again is reported again", seen[2] and seen[2].tuiFailed ~= nil, #seen)

-- Started at the command line on purpose: nothing failed, nothing to say.
seen = runShell("cli", false, { "logout" })
test("a CLI that nobody fell back to carries no failure", seen[1] and seen[1].tuiFailed == nil)

-- And after a failure, a later CLI start that is not a failure is clean.
seen = runShell("cli", true, { "tui", "tui", "logout" })
test("the first CLI (asked for) has no failure", seen[1] and seen[1].tuiFailed == nil)
test("the one after `tui` failed has it", seen[2] and seen[2].tuiFailed ~= nil)

-- The CLI prints what it is handed, under its banner.
do
  local h = assert(io.open("tos/shell/cli.lua", "rb"))
  local src = h:read("*a"):gsub("\r\n", "\n"); h:close()
  test("the CLI prints the reason it was handed",
    src:find("if ctx.tuiFailed then", 1, true) ~= nil
    and src:find("The full interface could not start: ", 1, true) ~= nil)
end

package.preload["shell.panels"] = nil
print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
