-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.notify                               ║
-- ║                                                                ║
-- ║  The facility that lets ANY program (a service, a mesh         ║
-- ║  handler, a sandboxed package) put a DOS-style dialog box in   ║
-- ║  the operator's face, instead of only writing to the polite    ║
-- ║  output area above the command line.                           ║
-- ║                                                                ║
-- ║  The rate limits are the load-bearing part and get the most    ║
-- ║  attention here: a modal any program can raise is a way to     ║
-- ║  lock an operator out of their own computer, so the floor      ║
-- ║  this layer enforces must not be escapable from above.         ║
-- ║                                                                ║
-- ║  Also pinned: multi-seat delivery (two shells, each raising    ║
-- ║  each notice once) and the TTL that stops a notice ambushing   ║
-- ║  someone long after it mattered.                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_notify.lua

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

local here = (arg and arg[0]) or "usr/lib/tests/test_notify.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local nf = loadMod("notify.lua")
if not nf then
  print("FAIL: could not load notify.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== kernel.notify Tests ===")
print()

-- ============================================================
-- 1. Sanitizing what a caller asks for
-- ============================================================
print("-- the spec --")

do
  local n, why = nf.sanitize({ message = "the reactor is on fire", from = "intercom" })
  test("a minimal spec is accepted", n ~= nil)
  eq("message kept", "the reactor is on fire", n and n.message)
  eq("source kept", "intercom", n and n.from)
  eq("title defaults to the source", "intercom", n and n.title)
  eq("one OK button by default", 1, n and #n.buttons)
  eq("...labelled OK", "OK", n and n.buttons[1])
  eq("style defaults to info", "info", n and n.style)
  eq("ttl defaults", nf.DEFAULT_TTL, n and n.ttl)

  test("a message is required", nf.sanitize({ from = "x" }) == nil)
  test("...and says so", select(2, nf.sanitize({ from = "x" })):find("message") ~= nil)
  test("an empty message is refused", nf.sanitize({ message = "" }) == nil)
  test("a non-table spec is refused", nf.sanitize("hello") == nil)
end

do
  -- Clamped, not rejected: the message is usually the point, so a slightly
  -- over-long one should still reach the operator.
  local n = nf.sanitize({ message = string.rep("x", nf.MAX_MESSAGE + 100),
                          title = string.rep("t", nf.MAX_TITLE + 50),
                          from = string.rep("f", 100) })
  eq("message clamped", nf.MAX_MESSAGE, #n.message)
  eq("title clamped", nf.MAX_TITLE, #n.title)
  test("source clamped", #n.from <= 24)

  local many = {}
  for i = 1, nf.MAX_BUTTONS + 5 do many[i] = "b" .. i end
  n = nf.sanitize({ message = "x", buttons = many })
  eq("buttons capped", nf.MAX_BUTTONS, #n.buttons)

  n = nf.sanitize({ message = "x", buttons = { "", 42, "Yes", "No" } })
  eq("malformed button labels dropped", 2, #n.buttons)
  eq("...keeping the good ones", "Yes", n.buttons[1])

  -- An unknown style must fall back to something the renderer knows, or
  -- the dialog would draw with a nil colour.
  n = nf.sanitize({ message = "x", style = "screaming" })
  eq("unknown style falls back", "info", n.style)
  n = nf.sanitize({ message = "x", style = "danger" })
  eq("a known style is kept", "danger", n.style)

  n = nf.sanitize({ message = "x", ttl = -5 })
  eq("negative ttl falls back", nf.DEFAULT_TTL, n.ttl)
  n = nf.sanitize({ message = "x", ttl = nf.MAX_TTL + 1 })
  eq("over-long ttl falls back", nf.DEFAULT_TTL, n.ttl)
  n = nf.sanitize({ message = "x", ttl = 30 })
  eq("a sane ttl is kept", 30, n.ttl)
end

-- ============================================================
-- 2. Posting and reading
-- ============================================================
print()
print("-- post / pending --")

nf._reset()
do
  eq("nothing pending on a fresh queue", 0, nf.depth())
  eq("high water starts at 0", 0, nf.highWater())

  local id = nf.post({ message = "hello", from = "mail" }, 100)
  test("post returns an id", type(id) == "number")
  eq("queued", 1, nf.depth())

  local list, high = nf.pending(0, 100)
  eq("one notice pending", 1, #list)
  eq("high water advanced", id, high)
  eq("the notice carries its source", "mail", list[1].from)

  -- Reading must NOT consume: on a multi-seat box each shell reads the
  -- same queue, and a pop-on-read would let whichever seat ticked first
  -- swallow the notice before the other saw it.
  local again = nf.pending(0, 100)
  eq("reading does not consume", 1, #again)
  eq("still queued", 1, nf.depth())

  -- A reader past the seq sees nothing.
  eq("cursor past the notice sees nothing", 0, #nf.pending(id, 100))
end

-- ============================================================
-- 3. Rate limits — the load-bearing part
-- ============================================================
print()
print("-- rate limits --")

nf._reset()
do
  -- Per-source gap: one chatty program can't monopolise the operator...
  local id1 = nf.post({ message = "one", from = "spammy" }, 100)
  test("first post accepted", id1 ~= nil)
  local id2, why = nf.post({ message = "two", from = "spammy" }, 101)
  test("same source 1s later is refused", id2 == nil)
  test("...and says why", type(why) == "string" and why:find("gap") ~= nil)

  -- ...but a DIFFERENT program is unaffected. A shared floor that let one
  -- misbehaving service mute everything else would be worse than none.
  local id3 = nf.post({ message = "three", from = "intercom" }, 101)
  test("a different source is not blocked", id3 ~= nil)

  local id4 = nf.post({ message = "four", from = "spammy" },
                      100 + nf.MIN_SOURCE_GAP)
  test("same source after the gap is accepted", id4 ~= nil)
end

nf._reset()
do
  -- Queue cap: refuse loudly rather than growing a queue that would take
  -- minutes of clicking to drain.
  local accepted = 0
  for i = 1, nf.MAX_QUEUE + 5 do
    -- Distinct sources so the per-source gap isn't what's being measured.
    if nf.post({ message = "m" .. i, from = "src" .. i }, 100) then
      accepted = accepted + 1
    end
  end
  eq("queue is capped", nf.MAX_QUEUE, accepted)
  eq("depth matches the cap", nf.MAX_QUEUE, nf.depth())
  local id, why = nf.post({ message = "one more", from = "another" }, 100)
  test("posting past the cap fails", id == nil)
  test("...and says the queue is full",
    type(why) == "string" and why:find("waiting") ~= nil)
end

nf._reset()
do
  -- The global quiet window: after ANY dialog is dismissed, the operator
  -- gets their keyboard back for MIN_GAP seconds no matter who wants it.
  nf.post({ message = "a", from = "one" }, 100)
  nf.post({ message = "b", from = "two" }, 100)
  local list = nf.pending(0, 100)
  eq("two pending", 2, #list)

  local first = nf.nextToShow(list, nil, 100)
  test("nothing shown yet -> show the first", first ~= nil)
  eq("...and it is the oldest", "one", first and first.from)

  local blocked, why = nf.nextToShow(list, 100, 100.5)
  test("another is refused inside the quiet window", blocked == nil)
  test("...and says how long is left",
    type(why) == "string" and why:find("quiet") ~= nil)

  local after = nf.nextToShow(list, 100, 100 + nf.MIN_GAP)
  test("after the quiet window the next one shows", after ~= nil)

  eq("nothing pending -> nothing to show", nil, (nf.nextToShow({}, nil, 100)))
end

-- ============================================================
-- 4. TTL — no ambushes
-- ============================================================
print()
print("-- expiry --")

nf._reset()
do
  nf.post({ message = "urgent now", from = "reactor", ttl = 30 }, 100)
  eq("live inside its ttl", 1, #nf.pending(0, 120))
  eq("gone once expired", 0, #nf.pending(0, 200))

  -- ...and nextToShow won't raise one either, even if a caller hands it a
  -- stale list.
  local stale = { { seq = 1, id = 1, at = 100, ttl = 30, from = "x",
                    message = "old", buttons = { "OK" }, style = "info" } }
  local pick, why = nf.nextToShow(stale, nil, 200)
  test("an expired notice is never raised", pick == nil)
  test("...and says so", type(why) == "string" and why:find("expired") ~= nil)

  eq("sweep drops it", 1, nf.sweep(200))
  eq("queue is empty after the sweep", 0, nf.depth())
  eq("sweeping again drops nothing", 0, nf.sweep(200))
end

-- ============================================================
-- 5. Settling — the operator's answer
-- ============================================================
print()
print("-- settle --")

nf._reset()
do
  local id = nf.post({ message = "Proceed?", from = "installer",
                       buttons = { "Yes", "No" } }, 100)
  eq("no result before the operator answers", nil, nf.result(id))
  test("settling reports success", nf.settle(id, 2))
  eq("the choice is readable by the poster", 2, nf.result(id))
  eq("settling removes it from the queue", 0, nf.depth())
  test("settling an unknown id is a no-op", not nf.settle(9999, 1))

  -- Settling for everyone is deliberate: on a multi-seat box the first
  -- operator to answer "the facility is on fire" answers for the site.
  local id2 = nf.post({ message = "fire", from = "intercom" }, 200)
  local seatA = nf.pending(0, 200)
  local seatB = nf.pending(0, 200)
  eq("both seats see it", 1, #seatA)
  eq("both seats really see it", 1, #seatB)
  nf.settle(id2, 1)
  eq("once answered it is gone for everyone", 0, #nf.pending(0, 200))
end

-- ============================================================
-- 6. Multi-seat cursors
-- ============================================================
print()
print("-- multi-seat --")

nf._reset()
do
  -- Two shells with independent cursors, exactly as events.lua keeps them.
  local seatA, seatB = 0, 0
  local id1 = nf.post({ message = "one", from = "a" }, 100)

  local listA = nf.pending(seatA, 100)
  eq("seat A sees it", 1, #listA)
  seatA = listA[1].seq                      -- A shows it, advances past it
  eq("seat A has moved on", 0, #nf.pending(seatA, 100))

  local listB = nf.pending(seatB, 100)
  eq("seat B still sees it (A didn't swallow it)", 1, #listB)
  seatB = listB[1].seq
  eq("seat B has now moved on", 0, #nf.pending(seatB, 100))

  -- A shell joining late starts at the high-water mark rather than
  -- replaying a backlog someone already dealt with.
  nf.post({ message = "two", from = "b" }, 100)
  local lateSeat = nf.highWater()
  eq("a late shell sees no backlog", 0, #nf.pending(lateSeat, 100))
  nf.post({ message = "three", from = "c" }, 100)
  eq("...but does see what comes next", 1, #nf.pending(lateSeat, 100))
end

nf._reset()
do
  -- The shell drain must advance its cursor only past the notice it
  -- ACTUALLY showed. Jumping to the queue's high-water mark would mark
  -- every other pending notice as seen after displaying one of them.
  nf.post({ message = "one", from = "a" }, 100)
  nf.post({ message = "two", from = "b" }, 100)
  nf.post({ message = "three", from = "c" }, 100)

  local seen, shownAt = 0, nil
  local shown = {}
  for tick = 1, 10 do
    local t = 100 + tick * nf.MIN_GAP
    local list = nf.pending(seen, t)
    local pick = nf.nextToShow(list, shownAt, t)
    if pick then
      shown[#shown + 1] = pick.from
      seen = pick.seq                        -- what events.lua does
      shownAt = t
      nf.settle(pick.id, 1)
    end
  end
  eq("every notice was eventually shown", 3, #shown)
  eq("in order: first", "a", shown[1])
  eq("in order: second", "b", shown[2])
  eq("in order: third", "c", shown[3])
end

-- ============================================================
-- 7. The `notify` sandbox capability
-- ============================================================
-- A sandboxed package command may interrupt the operator — but only
-- through a narrowed surface, and only under its own name.
print()
print("-- sandbox capability --")

do
  local function tryload(rel)
    for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
      local chunk = loadfile(p)
      if chunk then return chunk end
    end
  end
  nf._reset()
  package.loaded["kernel.notify"] = nf
  local sandboxChunk = tryload("tos/kernel/sandbox.lua")
  test("sandbox.lua loads", sandboxChunk ~= nil)

  if sandboxChunk then
    local sandbox = sandboxChunk()
    local env = sandbox.build({ caps = { notify = true }, pkgName = "intercom" })
    test("notify exposed with the cap", type(env.notify) == "table")
    test("post exposed", type(env.notify and env.notify.post) == "function")
    test("result exposed", type(env.notify and env.notify.result) == "function")
    do
      local n = 0
      for _ in pairs(env.notify or {}) do n = n + 1 end
      eq("exactly the two-function surface", 2, n)
    end
    -- The queue is other programs' business, and settle/_reset would let a
    -- package dismiss or wipe someone else's dialog.
    eq("pending NOT exposed", nil, env.notify and env.notify.pending)
    eq("settle NOT exposed", nil, env.notify and env.notify.settle)
    eq("_reset NOT exposed", nil, env.notify and env.notify._reset)

    local envNo = sandbox.build({ caps = {}, pkgName = "intercom" })
    eq("notify NOT exposed without the cap", nil, envNo.notify)

    -- #SEC — the source is stamped from the PACKAGE NAME and a program's
    -- own `from` is ignored. Two reasons: the name on an interrupting
    -- dialog must be trustworthy, and `from` is the rate-limit key, so a
    -- program that could choose it could evade its own gap by rotating it.
    local id = env.notify.post({ message = "hello", from = "kernel" })
    test("a package can post", id ~= nil)
    local list = nf.pending(0)
    eq("one notice queued", 1, #list)
    eq("source is the package name, NOT the claimed one", "intercom", list[1].from)

    -- Rate limits apply to packages exactly as they do to anything else —
    -- the cap grants the ABILITY to interrupt, never an exemption.
    local id2, why = env.notify.post({ message = "again" })
    eq("a package cannot evade the per-source gap", nil, id2)
    test("...and is told why", type(why) == "string")

    -- Spoofing the source to dodge the gap must not work either.
    local id3 = env.notify.post({ message = "sneaky", from = "somethingelse" })
    eq("rotating `from` does not reset the gap", nil, id3)

    test("posting a non-table is refused",
      select(1, env.notify.post("hello")) == nil)
  end
end

-- ============================================================
-- 8. Shell wiring
-- ============================================================
print()
print("-- shell wiring --")

do
  local function readUp(rel)
    for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
      local h = io.open(p, "r")
      if h then local s = h:read("a"); h:close(); return s end
    end
  end
  local regSrc = readUp("tos/shell/panels/commands.lua")
  local coreSrc = readUp("tos/shell/panels/commands/core.lua")
  local evSrc = readUp("tos/shell/panels/events.lua")
  test("commands.lua readable", regSrc ~= nil)
  test("core.lua readable", coreSrc ~= nil)
  test("events.lua readable", evSrc ~= nil)

  if regSrc and coreSrc and evSrc then
    local M = load(regSrc, "=commands.lua", "t")()
    local entry = M.entry("notify")
    test("notify is in the command registry", entry ~= nil)
    eq("notify is a core command", "core", entry and entry.category)
    -- Tier 1, not 0: interrupting everyone at the machine is a real action.
    eq("notify is tier 1 (not open to guests)", 1, entry and entry.tier)
    test("core.lua assigns C.notify",
      coreSrc:find("C.notify = function", 1, true) ~= nil)

    -- The panels loop must drain the SHARED facility, not any one add-on.
    test("the event loop drains kernel.notify",
      evSrc:find('require, "kernel.notify"', 1, true) ~= nil)
    test("the old intercom-specific popup probe is gone",
      evSrc:find("takePopup", 1, true) == nil)
    -- The drain must advance its cursor to the notice it showed, never to
    -- the queue's high-water mark (that would swallow the others).
    test("the drain advances the cursor by the shown notice",
      evSrc:find("S._noticeSeen = notice.seq", 1, true) ~= nil)
    -- And it must not paint while another process owns the seat.
    test("the drain respects suspendIdleDraw",
      evSrc:find("S._lastNotice", 1, true) ~= nil
      and evSrc:match("S%._lastNotice.-suspendIdleDraw") ~= nil)
    -- The quiet window must be stamped AFTER the (blocking) dialog closes.
    -- Stamped before, a slow dismissal would spend the operator's
    -- guaranteed keyboard time while they were still reading the box.
    test("the quiet window is stamped after the dialog returns",
      evSrc:match("dialogsMod%.dialog.-S%._noticeShownAt = computer%.uptime") ~= nil)
    test("...and not before it opens",
      evSrc:match("S%._noticeShownAt = nowS") == nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***") end
return failed == 0
