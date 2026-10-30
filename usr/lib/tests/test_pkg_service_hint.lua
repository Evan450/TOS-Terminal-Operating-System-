-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg install says when a service will start   ║
-- ║                                                                ║
-- ║  rc runs /etc/rc.d at boot, and an install only copies the     ║
-- ║  script there. So after `pkg install mail` the headless runner ║
-- ║  showed "Installed: mail", an inbox reading "service stopped   ║
-- ║  -- receive off", and a mail to it sitting unacknowledged, and ║
-- ║  nothing had said a reboot or `service start mail` was needed. ║
-- ║                                                                ║
-- ║  serviceHint is LIFTED from C.pkg and run on fake manifests.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_service_hint.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local h = assert(io.open("tos/shell/panels/commands/admin.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()
local from = src:find("local function serviceHint", 1, true)
local to = from and src:find("\n    end\n", from, true)
test("found serviceHint in admin.lua", from ~= nil and to ~= nil)
if not (from and to) then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end

local MANIFESTS = {
  mail = { kind = "service", files = { "/usr/lib/mail.lua", "/etc/rc.d/mail.lua" } },
  rshish = { kind = "service", files = { "/etc/rc.d/rshish.lua" },
             service = { defaultState = "disabled" } },
  tetris = { kind = "command", files = { "/usr/modules/tetris/init.lua" } },
  nodaemon = { kind = "service", files = { "/usr/lib/x.lua" } },
}
local out = {}
local env = {
  pkgMod = { info = function(n) return MANIFESTS[n] end },
  o = function(s) out[#out + 1] = s end,
  T = { dim = 1 }, ipairs = ipairs, tostring = tostring, type = type,
  string = string, table = table,
}
local hint = assert(load(src:sub(from, to + 8) .. "\nreturn serviceHint", "=hint", "t", env))()

print("=== pkg install says when a service will start ===")
print()

hint({ "mail" })
test("a service package names the next boot and the command",
  (out[1] or ""):find("next boot", 1, true) and (out[1] or ""):find("service start mail", 1, true), out[1])
out = {}; env.o = function(s) out[#out + 1] = s end
hint({ "rshish" })
test("one installed disabled says it is switched off",
  (out[1] or ""):find("switched off", 1, true) and (out[1] or ""):find("service start rshish", 1, true), out[1])
out = {}
hint({ "tetris", "nodaemon", "gone" })
test("a command, a service with no rc.d script, and an unknown name say nothing", #out == 0, out[1])
out = {}
hint(nil)
test("no names is fine", #out == 0)

test("the by-name install uses it", src:find("serviceHint(summary.installed)", 1, true) ~= nil)
test("the directory install uses it", src:find("serviceHint(new)", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
