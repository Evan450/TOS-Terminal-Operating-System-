-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `lang dump` says why a write was refused     ║
-- ║                                                                ║
-- ║  On the headless machine, as root, `lang dump                  ║
-- ║  /usr/lang/xx.lang` printed "Write failed: /usr/lang/xx.lang"  ║
-- ║  and nothing else. /usr is a protected system path (securefs   ║
-- ║  refuses even root without `protect off`), and the template's  ║
-- ║  own header told translators to save it there. Now the reason  ║
-- ║  is shown, a /usr/lang target gets the route that works, and   ║
-- ║  the template names it too. Drives the real command.           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_lang_dump_refusal.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"]  = { uptime = function() return 0 end, freeMemory = function() return 1e6 end,
                                totalMemory = function() return 2097152 end, beep = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
package.loaded["kernel.i18n"] = {
  keysSeen = function()
    return { { key = "login.username", default = "Username:" },
             { key = "desktop.files", default = "Files" } }
  end,
}

local REFUSAL = "Refused: writing to /usr is a protected system path."
local files = {}
local F = {
  writeFile = function(p, d)
    if p:sub(1, 5) == "/usr/" then return false, REFUSAL end
    files[p] = d; return true
  end,
  readFile = function(p) return files[p] end,
  exists = function(p) return files[p] ~= nil end,
}

local okC, register = pcall(require, "shell.panels.commands.core")
assert(okC and type(register) == "function", tostring(register))
local S = {
  K = {}, E = { push = function() end }, P = {}, F = F, D = {}, U = {}, NM = {},
  T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
  tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
}
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end, refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() return {} end,
  promptInput = function() return "" end,
  confirm = function() return true end, confirmTyped = function() return true end,
}
local C = {}
assert(pcall(register, C, S, deps))

local function run(...)
  local out = {}
  local ok, err = pcall(C.lang, { ... }, function(t) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n"), ok, err
end

print("=== `lang dump` says why a write was refused ===")
print()

local out, ok, err = run("dump", "/usr/lang/xx.lang")
test("`lang dump /usr/lang/xx.lang` runs", ok, err)
test("...says the write failed", out:find("Write failed: /usr/lang/xx.lang", 1, true) ~= nil, out)
test("...and shows the refusal's reason", out:find(REFUSAL, 1, true) ~= nil, out)
test("...and the route that works", out:find("protect off", 1, true) ~= nil
  and out:find("package", 1, true) ~= nil, out)

out = run("dump", "/home/root/x.lang")
test("a writable path writes the template", files["/home/root/x.lang"] ~= nil, out)
test("...which names the protected path and protect off for /usr/lang",
  files["/home/root/x.lang"] and files["/home/root/x.lang"]:find("protect off", 1, true) ~= nil)
test("...and carries the keys seen", files["/home/root/x.lang"]
  and files["/home/root/x.lang"]:find('["login.username"] = "Username:"', 1, true) ~= nil)

out = run("dump")
test("the default target is /tmp, and it succeeds", files["/tmp/lang-template.lang"] ~= nil
  and out:find("-> /tmp/lang-template.lang", 1, true) ~= nil, out)
test("...with no hint when nothing went wrong", not out:find("protect off", 1, true), out)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
