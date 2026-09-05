-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: confirm() puts the SAFE choice first         ║
-- ║                                                                ║
-- ║  Keyboard focus already started on No. The button ORDER was     ║
-- ║  { Yes, No }, so the leftmost button -- the one a click-through ║
-- ║  or a stray mouse press lands on -- was the destructive one.    ║
-- ║                                                                ║
-- ║  Reordering flipped the index-to-meaning mapping INSIDE         ║
-- ║  confirm() and nowhere else, because the boolean return kept    ║
-- ║  its meaning. That is precisely the sort of change that goes    ║
-- ║  wrong silently later, so both halves are pinned here: what     ║
-- ║  the buttons are, and which index means yes.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_dialog_confirm.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_dialog_confirm.lua"
local base = here:gsub("[^/\\]*$", "")
local dialogs
for _, p in ipairs({ base .. "../../../tos/shell/panels/dialogs.lua",
    "tos/shell/panels/dialogs.lua", "TOS-Dev/tos/shell/panels/dialogs.lua" }) do
  local chunk = loadfile(p); if chunk then dialogs = chunk(); break end
end
if not dialogs or not dialogs.confirm then
  print("FAIL: could not load dialogs.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== confirm(): safe choice first ===")
print()

-- Capture what confirm() asks dialog() for, and answer with a chosen index.
local seen
local realDialog = dialogs.dialog
local function stub(pickIndex)
  dialogs.dialog = function(S, opts)
    seen = opts
    return pickIndex
  end
end
local function restore() dialogs.dialog = realDialog end

-- ── Button order and defaults ──────────────────────────────────────
stub(1)
dialogs.confirm({}, "Delete everything?")
restore()

test("confirm asked for exactly two buttons", seen and #seen.buttons == 2)
test("the FIRST button is No (a click-through denies)", seen and seen.buttons[1] == "No")
test("the second button is Yes", seen and seen.buttons[2] == "Yes")
test("focus starts on the safe choice", seen and seen.default == 1)
test("Esc maps to the safe choice", seen and seen.escIndex == 1)
test("the style is 'danger' by default", seen and seen.style == "danger")

-- ── The index-to-meaning mapping ───────────────────────────────────
stub(1); local pickedFirst  = dialogs.confirm({}, "?"); restore()
stub(2); local pickedSecond = dialogs.confirm({}, "?"); restore()
test("choosing the first button means NO", pickedFirst == false)
test("choosing the second button means YES", pickedSecond == true)

-- Esc/close returns nil from the dialog loop; that must not read as yes.
stub(nil); local pickedNone = dialogs.confirm({}, "?"); restore()
test("dismissing without choosing means NO", pickedNone == false)

-- ── Opt-in to a yes default, for non-destructive questions ─────────
stub(2)
dialogs.confirm({}, "Save your work?", { default = "yes" })
restore()
test("default='yes' focuses Yes", seen and seen.default == 2)
test("...but Yes is still the second button", seen and seen.buttons[2] == "Yes")
test("...and Esc still means no", seen and seen.escIndex == 1)

-- ── Custom labels keep the same ordering ───────────────────────────
stub(1)
dialogs.confirm({}, "Wipe the disk?", { yes = "Wipe it", no = "Keep it" })
restore()
test("a custom safe label comes first", seen and seen.buttons[1] == "Keep it")
test("a custom destructive label comes second", seen and seen.buttons[2] == "Wipe it")

-- ══════════════════════════════════════════════════════════════════════
-- confirmTyped: the same box, but yes costs a typed word
-- ══════════════════════════════════════════════════════════════════════
--! The interactive loop needs a real screen and signal stream, so what
--! is checked here is the contract around it: it exists, it keeps the
--! safe choice first, and the callers that must not be downgraded to
--! y/N still are not. The loop itself is emulator work and is listed as
--! such in TODO.txt rather than pretended-at here.
print()
print("-- confirmTyped --")
do
  test("dialogs exports confirmTyped", type(dialogs.confirmTyped) == "function")

  local src
  for _, p in ipairs({ base .. "../../../tos/shell/panels/dialogs.lua",
      "tos/shell/panels/dialogs.lua", "TOS-Dev/tos/shell/panels/dialogs.lua" }) do
    src = readFileMaybe and readFileMaybe(p) or nil
    if not src then local h = io.open(p, "rb"); if h then src = h:read("*a"); h:close() end end
    if src then break end
  end
  test("dialogs.lua readable", src ~= nil)
  if src then
    local body = src:match("function M%.confirmTyped.-\nend\n") or src
    test("Cancel is the first button", body:find('opts%.no or "Cancel"') ~= nil)
    test("Confirm is the second", body:find('opts%.yes or "Confirm"') ~= nil)
    test("focus starts on Cancel", body:find("local buf, focus = \"\", 1") ~= nil)
    test("Esc returns false", body:find("if c == 1 or b == 17 then") ~= nil)
    test("it reuses drawDialog rather than a new look",
      body:find("drawDialog(S, style, title, lines, labels, focus", 1, true) ~= nil)
    test("Confirm is inert until the word matches",
      body:find("elseif matched then", 1, true) ~= nil)
    test("no first-letter hotkeys (they would eat the typing)",
      body:find("hot%[") == nil)
  end

  --! An open dialog used to wake the machine 20 times a second doing
  --! nothing, per box, for as long as someone took to read it.
  --! pullSignal(t) returns the moment a signal arrives -- t is only the
  --! idle ceiling -- so a long wait costs nothing in responsiveness and
  --! saves all of that call budget.
  if src then
    test("the dialog does not poll 20x a second",
      src:find("pullSignal(0.05)", 1, true) == nil)
    test("it waits on an event with a long idle ceiling",
      src:find("DIALOG_IDLE_WAIT", 1, true) ~= nil)
    local wait = tonumber(src:match("local DIALOG_IDLE_WAIT = ([%d%.]+)"))
    test("the ceiling is at least as patient as the kernel's 0.5s waits",
      type(wait) == "number" and wait >= 0.5)
    test("...but not infinite, so a corrupted box still redraws",
      type(wait) == "number" and wait < math.huge)
    test("a coroutine caller still yields to the scheduler",
      src:find("coroutine.yield()", 1, true) ~= nil)
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- Progress through a RUN of questions
-- ══════════════════════════════════════════════════════════════════════
--! A sequence of yes/no boxes with no visible end is what operators
--! start clicking through. Two lines telling them "3 of 7" buys an
--! answer they actually meant.
print()
print("-- progress --")
do
  local P = dialogs.progressLines
  test("progressLines exists", type(P) == "function")

  local function bar(line)
    return select(2, line:gsub("#", "")), select(2, line:gsub("%-", ""))
  end

  local l = P(1, 4, 20)
  test("returns a blank spacer then the bar", #l == 2 and l[1] == "")
  test("counts from 1, not 0", l[2]:find("1 of 4", 1, true) ~= nil)
  do
    local h, d = bar(l[2])
    -- The first prompt shows a step of progress, not an empty trough:
    -- you are ON question 1, which is itself progress through the run.
    test("the first prompt is already partly filled", h > 0 and d > 0)
  end

  local mid = P(3, 4, 20)
  test("the bar fills as the run advances", select(1, bar(mid[2])) > select(1, bar(l[2])))
  test("...and still shows where we are", mid[2]:find("3 of 4", 1, true) ~= nil)

  --! THE ONE THAT MATTERS. The bar used to measure answered-so-far, so
  --! the final prompt sat at 3-of-4 filled and never completed no matter
  --! what you installed -- which reads as stuck, not as thorough.
  do
    local last = P(4, 4, 20)
    local h, d = bar(last[2])
    test("the LAST prompt shows a full bar", h == 20 and d == 0)
    test("...while still on screen, before the box goes away",
      last[2]:find("4 of 4", 1, true) ~= nil)
  end
  do
    local h, d = bar(P(7, 7, 20)[2])
    test("full at the end of a longer run too", h == 20 and d == 0)
  end
  do
    -- Monotonic: never goes backwards partway through a run.
    local prev = -1
    local okMono = true
    for i = 1, 7 do
      local h = select(1, bar(P(i, 7, 20)[2]))
      if h < prev then okMono = false end
      prev = h
    end
    test("progress never goes backwards", okMono)
  end

  -- Bad input must not crash a dialog; it just means "no progress shown".
  test("nil index yields no lines", #P(nil, 4, 20) == 0)
  test("nil total yields no lines", #P(1, nil, 20) == 0)
  test("zero total yields no lines", #P(1, 0, 20) == 0)

  -- ASCII only: the Release minifier and 4-bit GPUs both mangle
  -- box-drawing characters mid-string.
  local ok = true
  for i = 1, #mid[2] do
    local b = mid[2]:byte(i)
    if b < 32 or b > 126 then ok = false end
  end
  test("the bar is pure ASCII", ok)
end

-- ── The callers ────────────────────────────────────────────────────
print()
print("-- destructive commands use a box, and flash still demands the word --")
do
  local function slurp(rel)
    for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
      local h = io.open(pre .. rel, "rb")
      if h then local s = h:read("*a"); h:close(); return s end
    end
  end
  local admin  = slurp("tos/shell/panels/commands/admin.lua")
  local extras = slurp("tos/shell/panels/commands/extras.lua")
  test("admin.lua readable", admin ~= nil)
  test("extras.lua readable", extras ~= nil)

  if admin then
    test("flash requires the typed word 'flash'",
      admin:find('confirmTyped%(.-"flash"') ~= nil or admin:find('"flash",') ~= nil)
    test("the not-a-BIOS override requires the typed word 'force'",
      admin:find('"force",') ~= nil)
    test("reclaim --apply asks before deleting", admin:find("Permanently delete", 1, true) ~= nil)
    test("userdel asks in a box", admin:find("Delete the account", 1, true) ~= nil)
    -- The regression that matters: nobody quietly softens these to y/N.
    test("flash was NOT downgraded to a plain confirm",
      admin:find('confirmBox%(%s*"Overwrite this machine') == nil)
  end
  if admin then
    -- The per-package run: box preferred, prompt kept, progress passed,
    -- and the box held up between questions.
    test("per-package install prefers the box",
      admin:find('title = "Install from media"', 1, true) ~= nil)
    test("...and keeps the one-line prompt as a fallback",
      admin:find('"? %[y/N%]: ", 4%)') ~= nil)
    test("...passes progress so the run has a visible end",
      admin:find("progress = %(index and total") ~= nil)
    test("...and does not repaint between questions",
      admin:find("index < total) and false or nil", 1, true) ~= nil)
    test("...showing the FULL path, not just the disk",
      admin:find('"From:" .. "', 1, true) ~= nil)
    test("the fallback prompt shows position too",
      admin:find('%(%%d/%%d%)') ~= nil)
  end

  if extras then
    test("TBFS format asks in a box", extras:find("Format drive", 1, true) ~= nil)
    test("raw-drive install asks in a box", extras:find("Erase and install", 1, true) ~= nil)
    test("no bare [y/N] prompts remain in extras",
      extras:find("%[y/N%]: \", 4%) or \"n\"\n%s*if") == nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
