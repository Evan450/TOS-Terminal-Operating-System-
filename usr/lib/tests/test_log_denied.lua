-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `log denied` shows the refusals, and only    ║
-- ║                                                                ║
-- ║  The sandbox writes "denied: <program> wanted <thing>" to the  ║
-- ║  log (462cfcf) and securefs "READ/WRITE denied: <path>", but   ║
-- ║  they sat among everything else. The TODO's AUDIT LOG FOR      ║
-- ║  CAPABILITY DENIALS asked for one place to read what was       ║
-- ║  refused, to whom, when. Drives the real `log` command.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_log_denied.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end, freeMemory = function() return 1e6 end,
                                pullSignal = function() return nil end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
package.loaded["kernel.screen"]  = {}
package.loaded["kernel.display"] = {}
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 },
  currentSession = function() return { user = "root", tier = 3 } end }

local LOG = table.concat({
  "[   10.1][INF][pkg] Installed ttt v1.0.0 (2 files)",
  "[   12.4][WRN][sandbox] denied: ttt wanted component",
  "[   13.0][INF][kernel] Seat 1: loading shell",
  "[   14.2][WRN][securefs] WRITE denied: /etc/passwd (system path)",
  "[   15.9][WRN][securefs] READ denied: /root/notes (not yours)",
  "[   16.0][WRN][kernel] Something else was denied: not a refusal line",
  "[   17.3][WRN][sandbox] denied: stock wanted peripheral.inventory",
}, "\r\n") .. "\r\n"   -- CRLF on purpose: what a Windows-hosted disk can hold
local files = { ["/var/log/kernel.log"] = LOG }

local okR, register = pcall(require, "shell.panels.commands.admin")
test("admin.lua loads", okR and type(register) == "function", register)
if not (okR and type(register) == "function") then print("*** TESTS FAILED ***"); os.exit(1) end
local viewed, viewedLabel
local S = {
  K = { getLog = function() return { flush = function() end } end },
  E = { push = function() end }, P = {}, D = {},
  F = { exists = function(p) return files[p] ~= nil end, readFile = function(p) return files[p] end },
  U = package.loaded["kernel.users"],
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local C = {}
register(C, S, {
  rp = function(p) return p end, refreshBrowser = function() end,
  openViewTab = function(buf, label) viewed, viewedLabel = buf, label end,
  openEditTab = function() end,
  adminOnly = function() return true end, rootOnly = function() return true end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end, makeProgramEnv = function() return {} end,
})
local function run(...)
  viewed, viewedLabel = nil, nil
  local out = {}
  C.log({ ... }, function(t) out[#out + 1] = tostring(t) end)
  local rows = {}
  for _, r in ipairs(viewed or {}) do rows[#rows + 1] = r[1] end
  return table.concat(rows, "\n"), table.concat(out, "\n")
end

print("=== log denied ===")
local shown = run("denied")
test("it opens a view", viewedLabel == "log denied", viewedLabel)
test("with the count", shown:find("(4)", 1, true) ~= nil, shown)
test("the sandbox's refusals", shown:find("ttt wanted component", 1, true) ~= nil
  and shown:find("stock wanted peripheral.inventory", 1, true) ~= nil, shown)
test("securefs's refusals", shown:find("WRITE denied: /etc/passwd", 1, true) ~= nil
  and shown:find("READ denied: /root/notes", 1, true) ~= nil, shown)
test("and nothing else", not shown:find("Installed ttt", 1, true)
  and not shown:find("loading shell", 1, true) and not shown:find("Something else", 1, true), shown)
test("each with its time", shown:find("12.4", 1, true) ~= nil, shown)
test("no stray carriage returns", not shown:find("\r", 1, true))

shown = run("denied", "1")
test("log denied 1 is the newest only", shown:find("stock wanted", 1, true) ~= nil
  and not shown:find("ttt wanted", 1, true), shown)

files["/var/log/kernel.log"] = "[    1.0][INF][kernel] booted\n"
local _, said = run("denied")
test("a clean log says so", said:find("Nothing has been refused", 1, true) ~= nil, said)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
