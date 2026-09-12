-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a redirect reports what the write did         ║
-- ║                                                                ║
-- ║  `cmd > file` checked the ACL, wrote through securefs, and said ║
-- ║  "Output written" whatever the write returned -- so the         ║
-- ║  protected-path guard refusing an ADMIN's `ls > /etc/passwd`    ║
-- ║  (the ACL allows ADMIN into /etc; the guard does not) was       ║
-- ║  reported as a success (Sep 2026 pentest). Drives the REAL      ║
-- ║  executor and kernel.pipe.                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_redirect_result.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

-- Stubs for the executor's module dependencies (as test_executor_invalidate).
_G._TOS = _G._TOS or {}
package.loaded["shell.panels.helpers"] = {
  routeOutput = function(n, maxInline)
    if n == 0 then return "clear"
    elseif n == 1 then return "status"
    elseif n <= (maxInline or 8) then return "inline"
    else return "tab" end
  end,
  expandBuf = function(_, buf) return buf end,
  canWrite = function() return true end,      -- the ACL says yes; the write decides
  refreshBrowser = function() end,
  expandAlias = function(_, parts) return parts end,
  resolveProgram = function() return nil end,
  clearFailure = function(St) if St then St.lastFailure = nil end end,
  noteFailure = function(St, cmd, text)
    if St and not St.lastFailure then St.lastFailure = { cmd = cmd, text = text } end
  end,
}
package.loaded["shell.panels.editor"] = { openViewTab = function() end }
package.loaded["kernel.pkg"] = {
  getCommand = function() return nil end,
  getCommandScreen = function() return nil end,
}

package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local executorMod = require("shell.panels.executor")

-- A disk behind securefs: /etc is refused by the protected-path guard.
local disk = {}
local REFUSAL = "Refused: writing to /etc is a protected system path.  [E-402 ERR_PATH_PROTECTED]"
local function write(p, c, append)
  if p:sub(1, 5) == "/etc/" then return false, REFUSAL end
  disk[p] = (append and (disk[p] or "") or "") .. c
  return true
end
local S = {
  W = 80, H = 25, T = { error = "ERR", highlight = "OK", fg = "FG" }, cwd = "/",
  F = { join = function(a, b) return a .. "/" .. b end, exists = function() return false end,
        writeFile = function(p, c) return write(p, c, false) end,
        appendFile = function(p, c) return write(p, c, true) end },
  D = {},
}
local exec = executorMod.build(S, {
  rp = function(p) return p end,
  makeProgramEnv = function() return {} end,
  C = { hello = function(_, o) o("hi") end },
})

print("=== a redirect reports what the write did ===")
print()
exec("hello > /tmp/out.txt")
test("a redirect that lands says so", S.lastOut and S.lastOut[1] == "Output written to /tmp/out.txt")
test("...and the file holds the output", disk["/tmp/out.txt"] == "hi\n")

S.lastOut = nil
exec("hello > /etc/passwd")
test("a redirect the protected-path guard refuses does NOT say it was written",
  S.lastOut ~= nil and not S.lastOut[1]:find("Output written", 1, true))
test("...it shows the refusal, as an error",
  S.lastOut ~= nil and S.lastOut[2] == "ERR" and S.lastOut[1]:find("protected system path", 1, true) ~= nil)
test("...and nothing was written", disk["/etc/passwd"] == nil)

S.lastOut = nil
exec("hello >> /tmp/out.txt")
test("an append that lands says so, and appends",
  S.lastOut and S.lastOut[1] == "Output written to /tmp/out.txt" and disk["/tmp/out.txt"] == "hi\nhi\n")

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
