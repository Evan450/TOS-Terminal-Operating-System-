-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Kiosk ACL enforcement               ║
-- ║                                                        ║
-- ║  Kiosk mode previously built its command env with      ║
-- ║    F        = _G._TOS.fs           (raw, ACL-bypassing) ║
-- ║    canRead  = function() return true end               ║
-- ║  so a default-allowed `cat` let a GUEST kiosk user read ║
-- ║  /etc/users.dat, /etc/trust.dat, or any home dir.       ║
-- ║                                                        ║
-- ║  The fix routes F through securefs and canRead/canWrite ║
-- ║  through helpers.canAccess against the kiosk session.   ║
-- ║  This test loads the REAL kiosk module, drives it with  ║
-- ║  stub kernel/securefs/users, and asserts:               ║
-- ║   1. F is the securefs instance (not the raw fs)        ║
-- ║   2. a read denied by securefs is refused (no bypass)   ║
-- ║   3. writes are refused outright (kiosk is read-only)   ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_kiosk_acl.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_kiosk_acl.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- ── Stubs ────────────────────────────────────────────────────────────
local RAW_FS = { __tag = "RAW" }      -- the raw, ACL-bypassing fs

-- securefs: only /public is readable; everything else denied. Tracks the
-- last path it was asked about so we can prove the read went THROUGH it.
local securefsCalls = {}
local SECUREFS = {
  __tag = "SECUREFS",
  exists = function(p) securefsCalls[#securefsCalls+1] = "exists:" .. p; return true end,
  isDirectory = function() return false end,
  readFile = function(p)
    securefsCalls[#securefsCalls+1] = "read:" .. p
    if p:sub(1, 7) == "/public" then return "PUBLIC-OK" end
    return nil, "Permission denied"
  end,
  list = function() return {} end,
}

-- users module: GUEST session; canAccessAs lets reads of /public only.
local kioskSession = { user = "kiosk", tier = 0, home = "/public" }
local USERS = {
  getSession = function(tok) if tok == "kiosk-token" then return kioskSession end end,
  currentSession = function() return kioskSession end,
  canAccessAs = function(sess, path, mode)
    if not sess then return false, "no session" end
    if mode == "r" and path:sub(1, 7) == "/public" then return true end
    return false, "denied by ACL"
  end,
}

-- Minimal display the kiosk pulls from kernel.getDisplay(). We never enter
-- the input loop, so only getTheme/getSize are exercised during build.
local DISPLAY = {
  getTheme = function() return { fg = 1, bg = 0, error = 9, title = 3, dim = 8 } end,
  getSize  = function() return 80, 25 end,
  clear = function() end, fill = function() end, set = function() end,
}

_G._TOS = {
  fs = RAW_FS, securefs = SECUREFS, users = USERS,
  config = {}, net = {}, process = { currentSession = function() return kioskSession end },
}

package.loaded["computer"] = { uptime = function() return 0 end, pullSignal = function() return nil end }

-- Stub the command builder so we can capture the S/deps the kiosk assembles
-- without dragging in the whole panels command surface. We capture, then
-- abort run() (via error) BEFORE it enters its infinite input loop.
local capturedS, capturedDeps
package.loaded["shell.panels.commands"] = {
  build = function(S, deps)
    capturedS, capturedDeps = S, deps
    error("__captured__")  -- bail out before the input loop
  end,
}

-- Mirror the real core.lua `cat`: gate on canRead, then read through F.
local function kioskCat(args, o)
  local p = capturedDeps.rp(args[1])
  if not capturedDeps.canRead(p, o) then return end
  local c = capturedS.F.readFile(p)
  if c then o(c, 1) else o("Cannot read", 9) end
end

-- Real helpers (the ACL bridge the fix relies on).
package.loaded["shell.panels.helpers"] = tryload("tos/shell/panels/helpers.lua")()

local kioskChunk = tryload("tos/shell/kiosk.lua")
if not kioskChunk then
  print("FAIL: could not load kiosk.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local kiosk = kioskChunk()

-- ── Drive kiosk.run just far enough to capture S/deps ────────────────
-- run() builds S/deps (calling our stub build, which captures then errors
-- out before the infinite input loop). We pcall it and ignore the abort.
local kernel = { getDisplay = function() return DISPLAY end }
pcall(kiosk.run, kernel, "kiosk-token")

print("=== Kiosk ACL Tests ===")
print()

if not capturedS then
  print("FAIL: kiosk.run never called commands.build")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- 1. F must be securefs, not the raw ACL-bypassing fs.
test("F is securefs (not raw fs)", "SECUREFS", capturedS.F.__tag)
test("st is the token (not the session object)", "kiosk-token", capturedS.st)

-- 2. A read of a denied path is refused (no raw-fs bypass).
local catOut = {}
kioskCat({ "/etc/users.dat" }, function(line) catOut[#catOut+1] = tostring(line) end)
local deniedSecret = true
for _, l in ipairs(catOut) do if l == "PUBLIC-OK" or l:find("users") then deniedSecret = false end end
test("cat of /etc/users.dat is refused", true, deniedSecret)

-- 2b. A read of an allowed path still works (no over-blocking).
local okOut = {}
kioskCat({ "/public/readme" }, function(line) okOut[#okOut+1] = tostring(line) end)
test("cat of /public/readme returns content", "PUBLIC-OK", okOut[1])

-- 3. canRead delegates to the ACL: /public allowed, /root denied.
test("canRead /public/info  -> allowed", true,  capturedDeps.canRead("/public/info"))
test("canRead /root/secret  -> denied",  false, capturedDeps.canRead("/root/secret"))
test("canRead /etc/users.dat-> denied",  false, capturedDeps.canRead("/etc/users.dat"))

-- 4. Writes are refused outright (kiosk read-only), regardless of path.
test("canWrite /public/x    -> denied",  false, capturedDeps.canWrite("/public/x"))
test("canAccess w mode      -> denied",  false, capturedDeps.canAccess("/public/x", "w"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
