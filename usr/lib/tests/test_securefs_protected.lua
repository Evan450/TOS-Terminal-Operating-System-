-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: securefs protected-target guard      ║
-- ║                                                        ║
-- ║  #REV — /home, /root, /public are NODE-protected (the   ║
-- ║  dir itself can't be removed/overwritten) but files     ║
-- ║  INSIDE them follow the per-user ACL. The old subtree    ║
-- ║  rule blocked every write under them, so users could     ║
-- ║  never save ~/.theme.cfg etc. ("WRITE denied            ║
-- ║  (protected): /root/.theme.cfg"). System trees           ║
-- ║  (/tos, /etc, /usr, /var) stay subtree-protected.        ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_securefs_protected.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.loaded["component"] = { list = function() return function() return nil end end }

local here = (arg and arg[0]) or "usr/lib/tests/test_securefs_protected.lua"
local base = here:gsub("[^/\\]*$", "")
local securefs
for _, p in ipairs({ base .. "../../../tos/kernel/securefs.lua",
    "tos/kernel/securefs.lua", "TOS-Dev/tos/kernel/securefs.lua" }) do
  local chunk = loadfile(p); if chunk then securefs = chunk(); break end
end
if not securefs or not securefs._isProtectedTarget then
  print("FAIL: could not load securefs / _isProtectedTarget missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local guard = securefs._isProtectedTarget

print("=== securefs protected-target Tests ===")
print()

-- Node-protected roots: the dir node itself is guarded...
test("/root node blocked", "/root", guard("/root"))
test("/home node blocked", "/home", guard("/home"))
test("/public node blocked", "/public", guard("/public"))

-- ...but files/subdirs INSIDE them are NOT guarded (ACL governs them).
test("/root/.theme.cfg writable (the bug)", nil, guard("/root/.theme.cfg"))
test("/root/.profile.cfg writable", nil, guard("/root/.profile.cfg"))
test("/home/alice/.theme.cfg writable", nil, guard("/home/alice/.theme.cfg"))
test("/home/alice/notes.txt writable", nil, guard("/home/alice/notes.txt"))
test("/public/shared.txt writable", nil, guard("/public/shared.txt"))

-- System trees stay subtree-protected (defence in depth).
test("/tos node blocked", "/tos", guard("/tos"))
test("/tos/kernel/init.lua blocked", "/tos", guard("/tos/kernel/init.lua"))
test("/etc/users.dat... still guarded subtree-wise except exempt",
  nil, guard("/etc/users.dat"))   -- exempt (admins add accounts)
test("/etc/secret.dat blocked", "/etc", guard("/etc/secret.dat"))
-- (returns the FIRST matching root, so a nested system path reports its
-- top-level root — still "blocked", which is what matters.)
test("/usr/lib/x.lua blocked", true, guard("/usr/lib/x.lua") ~= nil)
test("/var/pkg/installed/x blocked", true, guard("/var/pkg/installed/x") ~= nil)
test("/init.lua blocked", "/init.lua", guard("/init.lua"))

-- Tree-exempt carve-outs under /var stay writable (log rotation etc.).
test("/var/log/kernel.log writable", nil, guard("/var/log/kernel.log"))
test("/var/run/x.pid writable", nil, guard("/var/run/x.pid"))

-- Prefix-collision safety: /rootkit is NOT under /root.
test("/rootkit not treated as /root", nil, guard("/rootkit"))
test("/homework not treated as /home", nil, guard("/homework"))

-- #SEC — SRM's known-good baseline must NOT be writable through securefs.
-- It inherits /var's subtree protection today, which is exactly right: the
-- baseline is what `srm scan` compares the system against, so a user who
-- could rewrite it could tamper with a system file and then re-bless it.
-- SRM writes it through the raw kernel.fs instead, behind an admin gate.
-- Pinned here so a future TREE_EXEMPT entry for /var/srm/ can't open it up
-- by accident the way /var/log/ and /var/run/ legitimately are.
test("/var/srm/index.dat blocked", true, guard("/var/srm/index.dat") ~= nil)
test("/var/srm/store/tos/kernel/init.lua blocked",
  true, guard("/var/srm/store/tos/kernel/init.lua") ~= nil)
test("/var/srm node blocked", true, guard("/var/srm") ~= nil)

-- ══════════════════════════════════════════════════════════════════════
-- Operator override
-- ══════════════════════════════════════════════════════════════════════
--! The protected set is defence-in-depth against a tampered ADMIN
--! session, not a wall the machine's owner cannot get past. Root can
--! stand it down for their own session; admin cannot, or the defence
--! would be worth nothing.
print()
print("-- operator override --")
do
  local TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 }
  securefs.init({
    fs      = { normalize = function(p) return p end },
    users   = { TIER = TIER },
    log     = nil,
    process = nil,
  })

  local rootSess  = { user = "root",  tier = TIER.ROOT }
  local adminSess = { user = "admin", tier = TIER.ADMIN }
  local userSess  = { user = "bob",   tier = TIER.USER }

  -- Nothing armed: the guard behaves exactly as before for everyone.
  test("root sees /etc protected before arming", true, guard("/etc/newfile", rootSess) ~= nil)
  test("admin sees /etc protected", true, guard("/etc/newfile", adminSess) ~= nil)
  test("a nil session still hits the guard", true, guard("/etc/newfile", nil) ~= nil)

  -- Only root may arm it.
  test("admin cannot arm the override", false, (securefs.setOperatorOverride(adminSess, true)))
  test("a plain user cannot arm it", false, (securefs.setOperatorOverride(userSess, true)))
  test("no session cannot arm it", false, (securefs.setOperatorOverride(nil, true)))
  test("admin arming did not take effect", true, guard("/etc/newfile", adminSess) ~= nil)

  test("root can arm it", true, (securefs.setOperatorOverride(rootSess, true)))
  test("...and it reports as armed", true, securefs.operatorOverride(rootSess))

  -- The three refusals that prompted this, from the operator's own report.
  test("root may now create a file in /etc", nil, guard("/etc/newfile", rootSess))
  test("root may now clear /usr/man", nil, guard("/usr/man/oldpage", rootSess))
  test("root may now touch /usr", nil, guard("/usr", rootSess))
  test("root may now remove /tos", nil, guard("/tos/kernel/init.lua", rootSess))

  -- Per-session, so it never leaks to anyone else at the machine.
  test("admin is still blocked while root is armed", true, guard("/etc/newfile", adminSess) ~= nil)
  test("an un-sessioned caller is still blocked", true, guard("/etc/newfile", nil) ~= nil)
  test("another root-tier session is NOT armed", true,
    guard("/etc/newfile", { user = "root", tier = TIER.ROOT }) ~= nil)

  -- And it can be put back.
  test("root can disarm", true, (securefs.setOperatorOverride(rootSess, false)))
  test("...and the guard returns", true, guard("/etc/newfile", rootSess) ~= nil)
  test("...and it reports as disarmed", false, securefs.operatorOverride(rootSess))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
