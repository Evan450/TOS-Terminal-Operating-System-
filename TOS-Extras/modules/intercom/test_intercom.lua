-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: intercom (facility announcement system)     ║
-- ║                                                                ║
-- ║  1. The cue catalog in the operator's own notation:            ║
-- ║       fuel-low [0001] "Warning: Reactor fuel low." [0005] warn ║
-- ║     parse, round-trip, and survive a typo without losing the   ║
-- ║     rest of the catalog.                                       ║
-- ║  2. Severity ordering.                                         ║
-- ║  3. Tape: absolute seek on a relative-seek device, play, and a  ║
-- ║     stop scheduled at the cue's END (never a blocking wait).    ║
-- ║  4. Receive policy: minLevel filter, popup threshold, and the   ║
-- ║     cooldown that keeps an alarm storm off the operator's       ║
-- ║     keyboard without ever dropping a message from the log.      ║
-- ║  5. The spool.                                                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua TOS-Extras/modules/intercom/test_intercom.lua

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

local here = (arg and arg[0]) or "TOS-Extras/modules/intercom/test_intercom.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. rel, "TOS-Extras/modules/intercom/" .. rel,
      "modules/intercom/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

-- serialize is a kernel module the lib soft-requires; give it the real one
-- so the config/spool paths exercise the actual codec.
local function loadKernel(rel)
  for _, p in ipairs({ base .. "../../../TOS-Dev/tos/kernel/" .. rel,
      "TOS-Dev/tos/kernel/" .. rel, "../TOS-Dev/tos/kernel/" .. rel,
      "../tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end
local serialize = loadKernel("serialize.lua")
package.loaded["kernel.serialize"] = serialize

local ic = loadMod("usr/lib/intercom.lua")
if not (ic and serialize) then
  print("FAIL: could not load intercom.lua / serialize.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== intercom Tests ===")
print()

-- ============================================================
-- 1. The catalog
-- ============================================================
print("-- cue notation --")

do
  -- Exactly the line the operator wrote in the design discussion.
  local c, why = ic.parseCueLine('fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn')
  test("the operator's own notation parses", c ~= nil)
  if c then
    eq("name", "fuel-low", c.name)
    eq("start position", 1, c.start)
    eq("end position", 5, c.stop)
    eq("text", "Warning: Reactor fuel low.", c.text)
    eq("severity", "warn", c.severity)
  else
    print("     (" .. tostring(why) .. ")")
  end
end

do
  local c = ic.parseCueLine(
    'offline [0006] "Warning: Reactor offline. Facility on backup power generation." [0010] alert')
  test("the second example parses", c ~= nil)
  eq("multi-sentence text kept whole",
    "Warning: Reactor offline. Facility on backup power generation.", c and c.text)
  eq("alert severity", "alert", c and c.severity)
end

-- Leading zeros are how a person writes a cue list; dropping them is how a
-- person types one. Both must work.
eq("unpadded positions parse", 1, (ic.parseCueLine('a [1] "x" [5]') or {}).start)
eq("padded positions parse", 1, (ic.parseCueLine('a [0001] "x" [0005]') or {}).start)
eq("severity defaults to info", "info", (ic.parseCueLine('a [1] "x" [5]') or {}).severity)
eq("name is case-folded", "fuel-low", (ic.parseCueLine('FUEL-LOW [1] "x" [5]') or {}).name)

do
  -- Single quotes, so text containing a double quote is still writable.
  local c = ic.parseCueLine([[warn1 [1] 'He said "go".' [9] alert]])
  test("single-quoted text parses", c ~= nil)
  eq("inner double quotes survive", 'He said "go".', c and c.text)
end

-- Rejections, each with a reason the operator can act on.
do
  local c, why = ic.parseCueLine('bad [10] "x" [5]')
  test("end before start is rejected", c == nil)
  test("...and says why", type(why) == "string" and why:find("after") ~= nil)

  c, why = ic.parseCueLine('bad [1] "x" [5] screaming')
  test("unknown severity rejected", c == nil)
  test("...and lists the valid ones", type(why) == "string" and why:find("critical") ~= nil)

  c, why = ic.parseCueLine('bad [1] "" [5]')
  test("empty text rejected", c == nil)

  c, why = ic.parseCueLine('this is not a cue line at all')
  test("garbage rejected", c == nil)
  test("...with the expected format shown",
    type(why) == "string" and why:find("<name>", 1, true) ~= nil)

  c, why = ic.parseCueLine('long [1] "' .. string.rep("x", ic.MAX_TEXT + 1) .. '" [5]')
  test("over-long text rejected", c == nil)
end

-- Comments and blanks are skipped, not errors.
do
  local c, why = ic.parseCueLine('# a comment')
  test("comment skipped silently", c == nil and why == nil)
  c, why = ic.parseCueLine('   ')
  test("blank line skipped silently", c == nil and why == nil)
end

print()
print("-- catalog --")

do
  local blob = table.concat({
    "# my announcements",
    "",
    'fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn',
    'offline   [0006] "Warning: Reactor offline." [0010]  alert',
    "this line is broken",
    'evac      [0011] "Evacuate the facility." [0020]  critical',
  }, "\n")
  local cues, errors = ic.parseCatalog(blob)
  eq("good cues collected", 3, #cues)
  eq("the typo is reported", 1, #errors)
  eq("...on the right line", 5, errors[1] and errors[1].line)
  -- The whole point: one bad line must not silence the announcement system.
  eq("cues after the typo still parsed", "evac", cues[3] and cues[3].name)
  eq("file order preserved", "fuel-low", cues[1].name)

  eq("findCue by name", 6, (ic.findCue(cues, "offline") or {}).start)
  eq("findCue is case-insensitive", 6, (ic.findCue(cues, "OFFLINE") or {}).start)
  test("findCue on a miss is nil", ic.findCue(cues, "nope") == nil)
end

do
  -- A duplicate name is reported and the FIRST definition wins (so an
  -- accidental paste can't silently redirect an existing alarm).
  local cues, errors = ic.parseCatalog(table.concat({
    'a [1] "first" [5]',
    'a [6] "second" [9]',
  }, "\n"))
  eq("duplicate collapsed to one cue", 1, #cues)
  eq("the first definition wins", "first", cues[1].text)
  eq("duplicate reported", 1, #errors)
end

do
  -- Round-trip: what `intercom cue add` writes must be what a person can
  -- still hand-edit, and must re-parse identically.
  local original = {
    { name = "fuel-low", start = 1, stop = 5,
      text = "Warning: Reactor fuel low.", severity = "warn" },
    { name = "quoted", start = 6, stop = 9,
      text = 'He said "go".', severity = "info" },
  }
  local blob = ic.formatCatalog(original)
  local back, errs = ic.parseCatalog(blob)
  eq("round-trip: no errors", 0, #errs)
  eq("round-trip: same count", 2, #back)
  for i, c in ipairs(original) do
    eq("round-trip name " .. i, c.name, back[i].name)
    eq("round-trip start " .. i, c.start, back[i].start)
    eq("round-trip stop " .. i, c.stop, back[i].stop)
    eq("round-trip text " .. i, c.text, back[i].text)
    eq("round-trip severity " .. i, c.severity, back[i].severity)
  end
  test("catalog carries a header for the editor",
    blob:find("severity", 1, true) ~= nil and blob:sub(1, 1) == "#")
end

-- ============================================================
-- 2. Severity
-- ============================================================
print()
print("-- severity --")

test("info < warn", ic.rank("info") < ic.rank("warn"))
test("warn < alert", ic.rank("warn") < ic.rank("alert"))
test("alert < critical", ic.rank("alert") < ic.rank("critical"))
eq("unknown severity ranks 0", 0, ic.rank("apocalyptic"))
test("atLeast is inclusive", ic.atLeast("alert", "alert"))
test("atLeast rejects below", not ic.atLeast("warn", "alert"))
test("atLeast accepts above", ic.atLeast("critical", "alert"))
test("validSeverity", ic.validSeverity("critical") and not ic.validSeverity("loud"))

-- ============================================================
-- 3. The tape
-- ============================================================
print()
print("-- tape --")

-- A Computronics-shaped fake: seek is RELATIVE and clamps at both ends,
-- which is exactly why seekTo has to rewind first.
local function fakeDrive(size)
  local d = { pos = 0, size = size or 4096, playing = false,
              stops = 0, plays = 0, seeks = {} }
  d.getSize = function() return d.size end
  d.getPosition = function() return d.pos end
  d.isReady = function() return true end
  d.seek = function(n)
    d.seeks[#d.seeks + 1] = n
    local want = d.pos + n
    if want < 0 then want = 0 elseif want > d.size then want = d.size end
    local moved = want - d.pos
    d.pos = want
    return moved
  end
  d.play = function() d.playing = true; d.plays = d.plays + 1 end
  d.stop = function() d.playing = false; d.stops = d.stops + 1 end
  return d
end

do
  local d = fakeDrive(4096)
  d.pos = 2000                                   -- start somewhere else
  local ok = ic.seekTo(d, 1500)
  test("seekTo succeeds", ok)
  eq("landed on the absolute position", 1500, d.pos)

  d.pos = 10
  ic.seekTo(d, 0)
  eq("seekTo 0 rewinds fully", 0, d.pos)

  local ok2, why = ic.seekTo(d, 99999)
  test("off-tape position refused", not ok2)
  test("...and says the tape size", type(why) == "string" and why:find("4096") ~= nil)
end

do
  local d = fakeDrive(8192)
  local cue = { name = "x", start = 1024, stop = 1024 + 4096,
                text = "hi", severity = "info" }
  local scheduled = {}
  local ok, secs = ic.playCue(d, cue, {
    timer = function(delay, fn) scheduled[#scheduled + 1] = { delay = delay, fn = fn } end,
  })
  test("playCue succeeds", ok)
  eq("seeked to the cue start", 1024, d.pos)
  eq("playback started", 1, d.plays)
  -- 4096 bytes at the stock 4096 B/s = one second.
  eq("duration derived from the cue length", 1, secs)
  eq("a stop was SCHEDULED, not waited for", 1, #scheduled)
  eq("...at the end of the cue", 1, scheduled[1].delay)
  eq("drive still playing until the timer fires", true, d.playing)
  scheduled[1].fn()
  eq("timer stopped the drive", false, d.playing)
end

do
  -- A non-stock byte rate must change the stop time, not the seek.
  local d = fakeDrive(8192)
  local cue = { name = "x", start = 0, stop = 2048, text = "hi", severity = "info" }
  local delay
  ic.playCue(d, cue, { bytesPerSecond = 1024,
    timer = function(dl) delay = dl end })
  eq("duration honours bytesPerSecond", 2, delay)
end

do
  local d = fakeDrive(4096)
  d.isReady = function() return false end
  local ok, why = ic.playCue(d, { start = 0, stop = 10 })
  test("no tape in the drive is refused", not ok)
  test("...with a plain reason", type(why) == "string" and why:find("tape") ~= nil)
end

-- ============================================================
-- 4. Receive policy
-- ============================================================
print()
print("-- receive policy --")

local CFG = ic.normalizeCfg({ popupLevel = "alert", popupCooldown = 60,
                              minLevel = "info" })

do
  local p = ic.receivePlan(CFG, { severity = "info", text = "hi" }, nil, 100)
  test("info accepted", p.accept)
  test("info does not interrupt", not p.popup)

  p = ic.receivePlan(CFG, { severity = "alert", text = "!" }, nil, 100)
  test("alert accepted", p.accept)
  test("alert interrupts", p.popup)

  p = ic.receivePlan(CFG, { severity = "critical", text = "!!" }, nil, 100)
  test("critical interrupts", p.popup)
end

do
  -- The cooldown. This is the property the operator asked for by name:
  -- a failing reactor must not be able to lock them out of their computer.
  local p1 = ic.receivePlan(CFG, { severity = "critical" }, nil, 100)
  test("first alarm interrupts", p1.popup)

  local p2 = ic.receivePlan(CFG, { severity = "critical" }, 100, 110)
  test("a second alarm 10s later does NOT interrupt", not p2.popup)
  test("...but is still accepted and logged", p2.accept)
  test("...and says how long is left",
    type(p2.why) == "string" and p2.why:find("cooldown") ~= nil)

  local p3 = ic.receivePlan(CFG, { severity = "critical" }, 100, 161)
  test("after the cooldown it interrupts again", p3.popup)

  -- Boundary: exactly at the cooldown is expired, not still-cooling.
  local p4 = ic.receivePlan(CFG, { severity = "critical" }, 100, 160)
  test("cooldown boundary is inclusive", p4.popup)
end

do
  -- minLevel as an "only tell me if it matters" filter.
  local quiet = ic.normalizeCfg({ minLevel = "alert", popupLevel = "critical" })
  local p = ic.receivePlan(quiet, { severity = "warn" }, nil, 0)
  test("below minLevel is dropped entirely", not p.accept)
  p = ic.receivePlan(quiet, { severity = "alert" }, nil, 0)
  test("at minLevel is accepted", p.accept)
  test("...but below popupLevel does not interrupt", not p.popup)
end

do
  -- An announcement from a NEWER intercom with a severity we don't know
  -- must still be logged, never promoted to an interruption.
  local p = ic.receivePlan(CFG, { severity = "cataclysmic" }, nil, 0)
  test("unknown severity is not promoted to a popup", not p.popup)
end

do
  local cfg = ic.normalizeCfg({ popupLevel = "nonsense", popupCooldown = -5,
                                minLevel = 42 })
  eq("bad popupLevel falls back to the default",
    ic.DEFAULT_CFG.popupLevel, cfg.popupLevel)
  eq("bad cooldown falls back", ic.DEFAULT_CFG.popupCooldown, cfg.popupCooldown)
  eq("bad minLevel falls back", ic.DEFAULT_CFG.minLevel, cfg.minLevel)
  local ok = ic.normalizeCfg({ popupCooldown = 0 })
  eq("zero cooldown is legal (always interrupt)", 0, ok.popupCooldown)
end

-- ============================================================
-- 5. Spool + payload
-- ============================================================
print()
print("-- spool --")

do
  local list = {}
  for i = 1, ic.MAX_SPOOL + 25 do
    list = ic.spoolAppend(list, { text = "n" .. i, severity = "info" })
  end
  eq("spool is capped", ic.MAX_SPOOL, #list)
  eq("oldest pruned, newest kept", "n" .. (ic.MAX_SPOOL + 25), list[#list].text)
end

do
  local a = ic.newAnnouncement({ text = string.rep("x", ic.MAX_TEXT + 50),
                                 severity = "alert", from = "reactor" })
  eq("announcement text is truncated", ic.MAX_TEXT, #a.text)
  eq("severity carried", "alert", a.severity)
  eq("sender carried", "reactor", a.from)
  local b = ic.newAnnouncement({ text = "x", severity = "made-up" })
  eq("invalid severity falls back to info", "info", b.severity)
end

do
  local line = ic.formatLine({ severity = "alert", from = "reactor",
                               text = "Reactor offline." })
  test("formatLine shows the severity", line:find("ALERT", 1, true) ~= nil)
  test("formatLine shows the sender", line:find("reactor", 1, true) ~= nil)
  test("formatLine shows the words", line:find("Reactor offline.", 1, true) ~= nil)
end

-- ============================================================
-- 6. End-to-end deliver (no network, injected store)
-- ============================================================
print()
print("-- deliver --")

local function fakeStore()
  local files = {}
  local S
  S = {
    _files = files,
    exists = function(p) return files[p] ~= nil end,
    readFile = function(p) return files[p] end,
    writeFile = function(p, c) files[p] = c; return true end,
    writeFileAtomic = function(p, c) files[p] = c; return true end,
    makeDirectory = function() return true end,
  }
  return S
end

-- A stand-in for kernel.notify: records what the Intercom would put on the
-- operator's screen. Injected rather than mocked globally, so these cases
-- assert the actual hand-off (severity -> dialog style, the words, the cue).
local function fakeNotify(refuse)
  local N = { posts = {} }
  N.post = function(spec)
    if refuse then return nil, "refused by policy" end
    N.posts[#N.posts + 1] = spec
    return #N.posts
  end
  N.result = function() return nil end
  return N
end

do
  local store = fakeStore()
  local nfy = fakeNotify()
  local cfg = ic.normalizeCfg({ popupLevel = "alert", popupCooldown = 60 })
  local deps = { fs = store, serialize = serialize, cfg = cfg, notify = nfy }

  local plan = ic.deliver({ text = "all fine", severity = "info", from = "a" }, 0, deps)
  test("info delivered", plan.accept)
  eq("info raised no dialog", 0, #nfy.posts)
  eq("info was spooled", 1, #ic.loadSpool(store, serialize))

  plan = ic.deliver({ text = "REACTOR", severity = "critical", from = "a" },
                    10, { fs = store, serialize = serialize, cfg = cfg,
                          notify = nfy, lastPopupAt = nil })
  test("critical delivered", plan.accept)
  eq("critical raised a dialog", 1, #nfy.posts)
  eq("both are in the spool", 2, #ic.loadSpool(store, serialize))

  local box = nfy.posts[1]
  eq("the dialog is stamped as the intercom", "intercom", box.from)
  test("the dialog carries the words", box.message:find("REACTOR", 1, true) ~= nil)
  test("the title names the severity", box.title:find("CRITICAL", 1, true) ~= nil)
  -- Severity has to reach the RENDERER, not just the text: a critical
  -- announcement should look like one.
  eq("critical maps to the danger style", "danger", box.style)
  eq("one acknowledge button", 1, #box.buttons)
  test("an announcement expires rather than ambushing someone later",
    type(box.ttl) == "number" and box.ttl > 0)

  -- A second critical inside the cooldown: logged, no second interruption.
  plan = ic.deliver({ text = "AGAIN", severity = "critical", from = "a" },
                    20, { fs = store, serialize = serialize, cfg = cfg,
                          notify = nfy, lastPopupAt = 10 })
  test("second critical still accepted", plan.accept)
  eq("but did not interrupt again", 1, #nfy.posts)
  eq("and is still in the log", 3, #ic.loadSpool(store, serialize))
end

do
  -- An `alert` (not critical) should warn, not scream.
  -- _reset() clears the popup cooldown the previous block left behind: it
  -- lives in a module upvalue on purpose (it has to survive across
  -- deliveries), so each case that cares starts from a known clock.
  ic._reset()
  local store, nfy = fakeStore(), fakeNotify()
  ic.deliver({ text = "offline", severity = "alert", from = "a" }, 0,
    { fs = store, serialize = serialize, notify = nfy,
      cfg = ic.normalizeCfg({ popupLevel = "alert" }) })
  eq("alert raised a dialog", 1, #nfy.posts)
  eq("alert maps to the warn style", "warn", nfy.posts[1] and nfy.posts[1].style)
end

do
  -- notify REFUSING the post (its floor said the operator is already being
  -- interrupted enough) must not lose the announcement: still accepted,
  -- still spooled, and the plan says why it didn't interrupt.
  ic._reset()
  local store, nfy = fakeStore(), fakeNotify(true)
  local plan = ic.deliver({ text = "REACTOR", severity = "critical", from = "a" }, 0,
    { fs = store, serialize = serialize, notify = nfy,
      cfg = ic.normalizeCfg({ popupLevel = "alert" }) })
  test("a refused dialog does not lose the announcement", plan.accept)
  eq("...it is still spooled", 1, #ic.loadSpool(store, serialize))
  eq("...and the plan records the refusal", false, plan.raised)
  test("...with the reason", type(plan.why) == "string"
    and plan.why:find("refused", 1, true) ~= nil)
end

do
  -- The cue name travels to the screen: an operator hearing a tape play
  -- should be able to see which recording it was.
  local nfy = fakeNotify()
  ic.raise({ text = "Evacuate.", severity = "critical", cue = "evac" }, nfy)
  test("the dialog names the tape cue",
    nfy.posts[1].message:find("evac", 1, true) ~= nil)
end

do
  -- With no notify facility at all, raise fails cleanly instead of raising.
  local ok, err = ic.raise({ text = "x", severity = "alert" }, false)
  test("no notify facility -> nil, not an error", ok == nil)
  test("...with a reason", type(err) == "string")
end

-- ============================================================
-- 7. The panels tab
-- ============================================================
-- Draw is checked by CALLING it against a recording display, not by reading
-- the source. The bug this exists for is the boring one: display.fill is
-- (x, y, w, h, char, FG, BG) and display.set is (x, y, text, FG, BG), so a
-- colour passed one slot early paints the background colour as text and the
-- tab renders invisible on a real screen while every unit test still passes.
print()
print("-- panels tab --")

package.loaded["intercom"] = ic
package.loaded["shell.panels.tabs"] = {
  find = function() return nil end,
  close = function() end,
}
local app = loadMod("usr/lib/intercomapp.lua")
test("intercomapp loads", app ~= nil)

if app then
  eq("cueRow shows the severity tag", "WARN",
    app.cueRow({ name = "x", text = "y", severity = "warn" }, 40):match("%u+"))
  test("cueRow fits the width",
    #app.cueRow({ name = "long-cue-name", text = string.rep("z", 200),
                  severity = "critical" }, 30) <= 30)
  -- The tag is fixed-width text, not just a colour: this machine ends up on a
  -- 1-bit corridor screen where colour says nothing.
  test("cueRow tags a critical cue distinctly",
    app.cueRow({ name = "x", text = "y", severity = "critical" }, 40)
      :find("CRIT", 1, true) ~= nil)

  local calls = { fill = {}, set = {} }
  local T = setmetatable({}, { __index = function(_, k) return "color:" .. k end })
  local S = {
    W = 80, H = 24, T = T,
    -- VARARGS, deliberately: with declared parameters, select("#", x, y, ...)
    -- counts the parameter list and always returns the full arity no matter
    -- how few arguments the caller actually passed — which would make the
    -- arity assertions below silently vacuous. Only `...` sees the real count.
    D = {
      fill = function(...)
        local n = select("#", ...)
        calls.fill[#calls.fill + 1] = { n = n, fg = (select(6, ...)),
                                        bg = (select(7, ...)) }
      end,
      set = function(...)
        local n = select("#", ...)
        calls.set[#calls.set + 1] = { n = n, text = (select(3, ...)),
                                      fg = (select(4, ...)), bg = (select(5, ...)) }
      end,
    },
  }
  local tab = { type = "intercom", sel = 1, scroll = 0,
    cues = { { name = "fuel-low", start = 1, stop = 5,
               text = "Warning: Reactor fuel low.", severity = "warn" },
             { name = "evac", start = 11, stop = 20,
               text = "Evacuate.", severity = "critical" } },
    errors = { { line = 4, why = "bad line" } },
    log = { { severity = "alert", from = "reactor", text = "Reactor offline." } },
  }

  local okD, err = pcall(app.draw, S, tab)
  test("draw runs without error", okD)
  if not okD then print("     " .. tostring(err)) end
  test("draw painted something", #calls.fill > 0 and #calls.set > 0)

  local badFill, badSet = 0, 0
  for _, c in ipairs(calls.fill) do if c.n ~= 7 then badFill = badFill + 1 end end
  for _, c in ipairs(calls.set) do if c.n ~= 5 then badSet = badSet + 1 end end
  eq("every fill passes both colours (x,y,w,h,char,fg,bg)", 0, badFill)
  eq("every set passes both colours (x,y,text,fg,bg)", 0, badSet)
  -- A background in the foreground slot is the specific mistake; catch it by
  -- name rather than only by arity.
  local bgAsFg = 0
  for _, c in ipairs(calls.fill) do if c.fg == "color:bg" then bgAsFg = bgAsFg + 1 end end
  for _, c in ipairs(calls.set) do if c.fg == "color:bg" then bgAsFg = bgAsFg + 1 end end
  eq("no call paints with the background as its foreground", 0, bgAsFg)

  -- The content an operator needs must actually reach the screen.
  local painted = {}
  for _, c in ipairs(calls.set) do painted[#painted + 1] = tostring(c.text) end
  painted = table.concat(painted, "\n")
  test("the cue list is drawn", painted:find("fuel%-low") ~= nil)
  test("the catalog error is drawn", painted:find("bad line", 1, true) ~= nil)
  test("the heard log is drawn", painted:find("Reactor offline.", 1, true) ~= nil)
  test("the key hints are drawn", painted:find("test", 1, true) ~= nil)

  -- An empty catalog must explain itself, in the operator's own notation.
  calls.set = {}
  local empty = { cues = {}, errors = {}, log = {}, sel = 1, scroll = 0 }
  pcall(app.draw, S, empty)
  local emptyPaint = {}
  for _, c in ipairs(calls.set) do emptyPaint[#emptyPaint + 1] = tostring(c.text) end
  emptyPaint = table.concat(emptyPaint, "\n")
  test("empty catalog names the file", emptyPaint:find(ic.CUES_PATH, 1, true) ~= nil)
  test("empty catalog shows an example line",
    emptyPaint:find("[0001]", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***") end
return failed == 0
