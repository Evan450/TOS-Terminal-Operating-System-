-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the welcome is per ACCOUNT, not per machine ║
-- ║                                                                ║
-- ║  login.lua has always offered the tutorial after every         ║
-- ║  successful login. What made it "the machine's first boot      ║
-- ║  only" was the MARKER: one shared file at /etc/.tutorial_done. ║
-- ║  Root finished the walkthrough on the very first boot, and     ║
-- ║  every account created afterwards was told, in effect, that    ║
-- ║  someone else had already read their welcome.                  ║
-- ║                                                                ║
-- ║  The marker is per-account now, in the user's own home beside  ║
-- ║  ~/.profile.cfg. That also drops a privilege oddity: writing   ║
-- ║  /etc needed ADMIN tier, so a plain USER who finished the      ║
-- ║  tutorial could not record it — markDone logged a warning and  ║
-- ║  they were offered the walkthrough again at their next login.  ║
-- ║                                                                ║
-- ║  Two things this must NOT do: replay the tutorial for a root   ║
-- ║  who finished it before the split, and let one guest's session ║
-- ║  suppress the welcome for every guest after them.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_tutorial_per_user.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_tutorial_per_user.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 4e6 end, pullSignal = function() return nil end,
  beep = function() end }

local tut = require("shell.tutorial")

-- A filesystem that is just a set of paths that exist.
local function fsWith(...)
  local set = {}
  for _, p in ipairs({ ... }) do set[p] = true end
  return {
    _set = set,
    exists = function(p) return set[p] == true end,
    writeFile = function(p) set[p] = true; return true end,
    remove = function(p) set[p] = nil; return true end,
  }
end

local ROOT  = { user = "root",  home = "/root",        tier = 3 }
local ALICE = { user = "alice", home = "/home/alice",  tier = 1 }
local BOB   = { user = "bob",   home = "/home/bob",    tier = 1 }
local GUEST = { user = "guest", home = "/public", tier = 0, isGuest = true }
local LEGACY = "/etc/.tutorial_done"

print("=== the welcome is per account Tests ===")
print()

-- ── Where each account's marker lives ──────────────────────────────
print("-- each account remembers it in its own home --")
do
  eq("root",  "/root/.tutorial_done",       tut.markerFor(ROOT))
  eq("alice", "/home/alice/.tutorial_done", tut.markerFor(ALICE))
  eq("a trailing slash on home is not doubled", "/home/bob/.tutorial_done",
    tut.markerFor({ user = "bob", home = "/home/bob/" }))
  eq("guest has none — its home is shared", nil, tut.markerFor(GUEST))
  eq("...and neither does a session with no home", nil,
    tut.markerFor({ user = "x", home = "" }))
  eq("...nor one rooted at /", nil, tut.markerFor({ user = "x", home = "/" }))
  eq("...nor a non-session", nil, tut.markerFor(nil))
end

-- ── THE BUG: a second user on the same machine ─────────────────────
print()
print("-- a machine where root has already done the walkthrough --")
do
  local F = fsWith("/root/.tutorial_done")
  eq("root is not asked again", false, tut.shouldShow(F, ROOT))
  eq("alice, logging in for the first time, IS offered it",
    true, tut.shouldShow(F, ALICE))
  eq("...and so is bob, independently", true, tut.shouldShow(F, BOB))
end

print()
print("-- and once alice has seen it, only alice is settled --")
do
  local F = fsWith("/root/.tutorial_done", "/home/alice/.tutorial_done")
  eq("alice is done", false, tut.shouldShow(F, ALICE))
  eq("bob is still new", true, tut.shouldShow(F, BOB))
end

-- ── Migration: an existing box must not replay it for root ─────────
print()
print("-- upgrading a machine that used the old shared marker --")
do
  local F = fsWith(LEGACY)          -- pre-1.4 state: one shared file
  eq("root, who finished it back then, is not made to repeat it",
    false, tut.shouldShow(F, ROOT))
  eq("but alice never saw it and is offered it now",
    true, tut.shouldShow(F, ALICE))
  eq("...and bob too", true, tut.shouldShow(F, BOB))
end

print()
print("-- a fresh machine offers it to everyone --")
do
  local F = fsWith()
  eq("root", true, tut.shouldShow(F, ROOT))
  eq("alice", true, tut.shouldShow(F, ALICE))
end

-- ── Guest: shared home, so neither answer can be recorded ──────────
-- The failure to avoid is one guest suppressing the welcome for every
-- guest after them. Guest keeps the old machine-wide behaviour.
print()
print("-- guest --")
do
  eq("offered on a machine that has never completed it",
    true, tut.shouldShow(fsWith(), GUEST))
  eq("not offered once the machine has (the old behaviour, unchanged)",
    false, tut.shouldShow(fsWith(LEGACY), GUEST))
  eq("a private user's marker never settles it for guest",
    true, tut.shouldShow(fsWith("/home/alice/.tutorial_done"), GUEST))
end

-- ── Nothing writes the legacy path any more ────────────────────────
print()
print("-- the shared marker is read, never written --")
do
  local src
  for _, p in ipairs({ base .. "../../../tos/shell/tutorial.lua",
      "tos/shell/tutorial.lua", "TOS-Dev/tos/shell/tutorial.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("tutorial.lua is readable", src ~= nil)
  if src then
    test("the marker written is the per-account one",
      src:find("F.writeFile(marker", 1, true) ~= nil)
    test("...and no writeFile targets the legacy constant",
      src:find("writeFile(LEGACY_MARKER", 1, true) == nil)
    -- Matched WITHOUT the closing paren on purpose. This asserted
    -- `F.exists(LEGACY_MARKER)` exactly, which pinned the argument list
    -- rather than the behaviour it is named for, and failed the moment
    -- the session argument was added -- a fix, not a regression.
    test("the legacy path is still consulted for the migration",
      src:find("F.exists(LEGACY_MARKER", 1, true) ~= nil)

    -- #SEC — every securefs read here must carry the session. Without
    -- it securefs resolves no principal (first-boot login sets no
    -- current session, and the boot-session fallback is off once boot
    -- completes) and fails closed: root was denied its own
    -- /root/.tutorial_done while holding a valid root token.
    local reads = 0
    for _ in src:gmatch("F%.exists%(") do reads = reads + 1 end
    local sessioned = 0
    for _ in src:gmatch("F%.exists%([^)]-,%s*session%s*%)") do sessioned = sessioned + 1 end
    test(string.format("every F.exists passes the session (%d/%d)", sessioned, reads),
      reads > 0 and sessioned == reads)
  end
end

-- ── login passes the session through ───────────────────────────────
-- shouldShow cannot answer per-account if the caller never says whose
-- login it is. Checked at the source: driving login.run needs the whole
-- display + users stack.
print()
print("-- login tells it whose login this is --")
do
  local src
  for _, p in ipairs({ base .. "../../../tos/shell/login.lua",
      "tos/shell/login.lua", "TOS-Dev/tos/shell/login.lua" }) do
    local fh = io.open(p, "r")
    if fh then src = fh:read("*a"); fh:close(); break end
  end
  test("login.lua is readable", src ~= nil)
  if src then
    test("tryTutorial resolves the session from the token",
      src:find("usermod.getSession(token)", 1, true) ~= nil)
    test("...and hands it to shouldShow",
      src:find("tut.shouldShow(fs, session)", 1, true) ~= nil)
    -- The call sites were already universal; this is the guard that they
    -- stay that way, since the whole feature rests on it.
    local _, n = src:gsub("tryTutorial%(token%)", "")
    test("the tutorial is still offered on every login path ("
      .. n .. " call sites)", n >= 3)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
