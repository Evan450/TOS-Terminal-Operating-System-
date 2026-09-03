-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: /var/mail at-rest privacy (#SEC)        ║
-- ║                                                            ║
-- ║  E2E sealing protects mail IN FLIGHT; the delivered inbox  ║
-- ║  at /var/mail/<user>/inbox.dat is plaintext. The generic   ║
-- ║  /var system-path branch used to grant READ to any logged  ║
-- ║  -in session (even guest). Now: owner or ADMIN+ only, and  ║
-- ║  listing /var/mail hides other users' mailbox names (same  ║
-- ║  posture as /home).                                        ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_mail_privacy.lua   (from the TOS-Dev root)

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

package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end }
-- Resolve users.lua's own kernel.* requires (serialize etc.) from the
-- real tree, whether run from TOS-Dev or the tests dir.
package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

local here = (arg and arg[0]) or "usr/lib/tests/test_mail_privacy.lua"
local base = here:gsub("[^/\\]*$", "")
local users
for _, p in ipairs({ base .. "../../../tos/kernel/users.lua",
    "tos/kernel/users.lua", "TOS-Dev/tos/kernel/users.lua" }) do
  local chunk = loadfile(p); if chunk then users = chunk(); break end
end
if not users or not users.canAccessAs then
  print("FAIL: could not load users.lua / canAccessAs missing")
  print("Results: 0 passed, 1 failed"); return false
end

print("=== /var/mail privacy Tests ===")
print()

local T = users.TIER
local alice = { user = "alice", tier = T.USER }
local bob   = { user = "bob",   tier = T.USER }
local guest = { user = "guest", tier = T.GUEST }
local admin = { user = "boss",  tier = T.ADMIN }
local root  = { user = "root",  tier = T.ROOT }

local INBOX = "/var/mail/alice/inbox.dat"

-- ── Read: owner + ADMIN+ only ──────────────────────────────────────
test("owner reads own inbox", true, (users.canAccessAs(alice, INBOX, "r")))
test("other USER cannot read it", false, (users.canAccessAs(bob, INBOX, "r")))
test("guest cannot read it", false, (users.canAccessAs(guest, INBOX, "r")))
test("admin can read it", true, (users.canAccessAs(admin, INBOX, "r")))
test("root can read it", true, (users.canAccessAs(root, INBOX, "r")))
test("the mailbox dir itself is covered too", false,
  (users.canAccessAs(bob, "/var/mail/alice", "r")))

-- ── Write: system-path posture kept (ADMIN+), owner included denied ─
test("owner cannot securefs-write own inbox (delivery is raw fs)", false,
  (users.canAccessAs(alice, INBOX, "w")))
test("other USER cannot write it", false, (users.canAccessAs(bob, INBOX, "w")))
test("admin may write (system-path rule)", true,
  (users.canAccessAs(admin, INBOX, "w")))

-- ── Traversal can't dodge the branch ───────────────────────────────
test("dot-dot path still lands on the mailbox rule", false,
  (users.canAccessAs(bob, "/var/log/../mail/alice/inbox.dat", "r")))

-- ── /var/mail itself stays generically readable (names filtered at
--    the securefs.list layer, mirroring /home) ──────────────────────
test("listing gate: /var/mail root path readable (filter is in list)",
  true, (users.canAccessAs(bob, "/var/mail", "r")))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
