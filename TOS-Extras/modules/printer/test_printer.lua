-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: printer driver                                     ║
-- ║                                                            ║
-- ║  printerfmt.lua is pure, so all of it tests off-box.       ║
-- ║  printer.lua needs a component; it is exercised against a  ║
-- ║  FAKE OpenPrinter that reproduces the two behaviours that   ║
-- ║  actually shape the driver — it THROWS on failure rather    ║
-- ║  than returning an error, and it refuses a 21st line.       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua modules/printer/test_printer.lua   (from TOS-Extras root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end
local function ok(name, cond) test(name, true, cond and true or false) end

local here = (arg and arg[0]) or "modules/printer/test_printer.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. rel, "modules/printer/" .. rel,
      "TOS-Extras/modules/printer/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

local fmt = tryload("usr/lib/printerfmt.lua")()

print("=== Printer Driver Tests ===")
print()

-- ══════════════════════════════════════════════════════════════════════
-- printerfmt — measuring
-- ══════════════════════════════════════════════════════════════════════
do
  -- Widths transcribed from OpenPrinter's CharacterWidth table.
  test("default glyph is 5px", 5, fmt.width("a"))
  test("space is 3px", 3, fmt.width(" "))
  test("'i' is 1px", 1, fmt.width("i"))
  test("'l' is 2px", 2, fmt.width("l"))
  test("'I' is 3px (capital, narrow)", 3, fmt.width("I"))
  test("'.' is 1px", 1, fmt.width("."))
  test("'@' is 6px", 6, fmt.width("@"))
  test("widths sum with no inter-char spacing", 1 + 1, fmt.width("ii"))
  test("empty string is 0px", 0, fmt.width(""))
  test("non-string is 0px", 0, fmt.width(nil))
  test("charCount counts characters", 5, fmt.charCount("hello"))
  -- The page constants are the mod's, and the tests pin them so a change
  -- to either is a deliberate act.
  test("20 lines per page", 20, fmt.MAX_LINES)
  test("164 pixels per line", 164, fmt.MAX_WIDTH)
end

-- ══════════════════════════════════════════════════════════════════════
-- printerfmt — sanitizing
-- ══════════════════════════════════════════════════════════════════════
do
  test("control bytes are stripped", "ab", fmt.sanitize("a\1\2b"))
  test("DEL is stripped", "ab", fmt.sanitize("a\127b"))
  test("tabs expand to spaces", "a    b", fmt.sanitize("a\tb"))
  test("tab width is settable", "a  b", fmt.sanitize("a\tb", { tabWidth = 2 }))
  test("ordinary text is untouched", "Hello, base.", fmt.sanitize("Hello, base."))
  test("non-string sanitizes to empty", "", fmt.sanitize(nil))
  -- The section sign is OpenPrinter's formatting escape: kept by default
  -- (stripping it would delete formatting the document meant to have),
  -- removed on request.
  test("§ survives by default", "a\194\167cb", fmt.sanitize("a\194\167cb"))
  test("strip removes § and its code", "ab", fmt.sanitize("a\194\167cb", { strip = true }))
end

-- ══════════════════════════════════════════════════════════════════════
-- printerfmt — logical lines
-- ══════════════════════════════════════════════════════════════════════
do
  local l = fmt.lines("a\nb\nc")
  test("splits on newline", 3, #l)
  test("first line", "a", l[1])
  test("CRLF is handled", 2, #fmt.lines("a\r\nb"))
  test("lone CR is handled", 2, #fmt.lines("a\rb"))
  -- A file that ends in \n is not a document with a blank last line.
  test("trailing newline adds no line", 2, #fmt.lines("a\nb\n"))
  test("interior blank line is kept", 3, #fmt.lines("a\n\nb"))
  test("empty document has no lines", 0, #fmt.lines(""))
end

-- ══════════════════════════════════════════════════════════════════════
-- printerfmt — wrapping
-- ══════════════════════════════════════════════════════════════════════
do
  -- One pixel per character makes the arithmetic readable.
  local one = function(s) return #s end

  local w = fmt.wrap("aaa bbb ccc", 7, one)
  test("wraps at the budget", 2, #w)
  test("first wrapped line", "aaa bbb", w[1])
  test("second wrapped line", "ccc", w[2])

  test("a fitting line is not wrapped", 1, #fmt.wrap("abc", 100, one))
  test("an empty line stays one (blank) line", 1, #fmt.wrap("", 10, one))
  test("empty line's content is empty", "", fmt.wrap("", 10, one)[1])

  -- An over-wide token is HARD-SPLIT. The alternative — letting it
  -- through — means the printer clips it and the page still looks
  -- finished, which is the failure that loses the end of a hash.
  local h = fmt.wrap("abcdefghij", 4, one)
  test("over-wide word is split, not clipped", 3, #h)
  test("split piece respects the budget", "abcd", h[1])
  test("split keeps the tail", "ij", h[3])
  local joined = table.concat(h)
  test("hard split loses nothing", "abcdefghij", joined)

  -- Whitespace runs collapse (the printer has no tab stops and a run of
  -- spaces at a wrap point would print as a ragged left margin).
  test("multiple spaces collapse", "a b", fmt.wrap("a    b", 100, one)[1])

  -- Real measurement: 'i' is 1px, so far more of them fit than 'm's.
  local narrow = fmt.wrap(string.rep("i", 200), 164)
  local wide   = fmt.wrap(string.rep("m", 200), 164)
  ok("narrow glyphs need fewer lines than wide ones", #narrow < #wide)
end

-- ══════════════════════════════════════════════════════════════════════
-- printerfmt — pagination
-- ══════════════════════════════════════════════════════════════════════
do
  local lines = {}
  for i = 1, 45 do lines[i] = "line " .. i end
  local pages = fmt.paginate(lines, 20)
  test("45 lines is 3 pages", 3, #pages)
  test("first page is full", 20, #pages[1])
  test("last page holds the remainder", 5, #pages[3])
  test("exactly one page's worth is one page", 1, #fmt.paginate({ 1, 2 }, 2))
  -- An empty document still yields one page: "print nothing" should be a
  -- decision the caller makes, not a silent no-op inside layout.
  test("empty input is one empty page", 1, #fmt.paginate({}, 20))
  test("that page is empty", 0, #fmt.paginate({}, 20)[1])
end

-- ══════════════════════════════════════════════════════════════════════
-- printerfmt — whole-document layout
-- ══════════════════════════════════════════════════════════════════════
do
  local one = function(s) return #s end
  local body = {}
  for i = 1, 25 do body[i] = "line" .. i end
  local pages = fmt.layout(table.concat(body, "\n"), { measure = one, maxWidth = 100 })
  test("25 short lines spill onto 2 pages", 2, #pages)
  test("page one is full", 20, #pages[1])
  test("layout emits line tables", "line1", pages[1][1].text)
  test("layout carries the alignment", "left", pages[1][1].align)

  -- A form feed forces a page.
  local broken = fmt.layout("a\n\f\nb", { measure = one })
  test("form feed starts a new page", 2, #broken)
  test("page one has the first line", "a", broken[1][1].text)
  test("page two has the second", "b", broken[2][1].text)

  -- A break on an empty page must not emit a blank sheet: paper is real.
  local doubled = fmt.layout("\f\n\f\na", { measure = one })
  test("leading breaks cost no paper", 1, #doubled)

  -- A misspelled alignment is refused rather than silently left-aligned.
  local bad, badErr = fmt.layout("x", { align = "centre" })
  test("bad alignment returns nil", nil, bad)
  ok("bad alignment explains itself", tostring(badErr):find("centre") ~= nil)
  test("center is accepted", "center", fmt.align("center"))
  test("nil alignment defaults to left", "left", fmt.align(nil))

  test("empty document is still one page", 1, #fmt.layout("", {}))
end

-- ══════════════════════════════════════════════════════════════════════
-- printerfmt — cost
-- ══════════════════════════════════════════════════════════════════════
do
  local pages = {
    { { text = "a" }, { text = "b" } },
    { { text = "c", color = 0xFF0000 } },
  }
  local c = fmt.cost(pages, 1)
  test("paper is counted per page", 2, c.paper)
  -- The distinction the whole design rests on: colour is charged per
  -- COLOURED LINE, so a default colour would drain the colour cartridge
  -- on an all-black document.
  test("uncoloured lines cost black ink", 2, c.black)
  test("coloured lines cost colour ink", 1, c.color)
  local c3 = fmt.cost(pages, 3)
  test("copies multiply paper", 6, c3.paper)
  test("copies multiply ink", 6, c3.black)
  test("zero copies is treated as one", 2, fmt.cost(pages, 0).paper)
end

-- ══════════════════════════════════════════════════════════════════════
-- printer.lua against a fake OpenPrinter
-- ══════════════════════════════════════════════════════════════════════
-- The fake reproduces the two behaviours that shape the driver:
--   1. failures THROW (the mod raises Java exceptions, which reach Lua as
--      errors), so every call site has to be pcall'd;
--   2. the 21st writeln on a page is refused.
local function fakePrinter(opts)
  opts = opts or {}
  local p = {
    address = "fake-printer-0000",
    lines = {}, printed = {}, title = nil,
    paper = opts.paper or 64,
    black = opts.black or 100,
    color = opts.color or 100,
    failOnPage = opts.failOnPage,
    pagesDone = 0,
  }
  function p.clear() p.lines = {}; return true end
  function p.setTitle(t) p.title = t; return true end
  function p.writeln(text, color, align)
    if #p.lines >= 20 then error("To many lines.") end
    if color ~= nil and p.color <= 0 then error("Please load Ink.") end
    p.lines[#p.lines + 1] = { text = text, color = color, align = align }
    if color ~= nil then p.color = p.color - 1 else p.black = p.black - 1 end
    return true
  end
  function p.print(copies)
    copies = copies or 1
    p.pagesDone = p.pagesDone + 1
    if p.failOnPage and p.pagesDone == p.failOnPage then
      error("no empty output slot")
    end
    if p.paper < copies then error("Please load Paper.") end
    p.paper = p.paper - copies
    for _ = 1, copies do
      p.printed[#p.printed + 1] = { title = p.title, lines = p.lines }
    end
    return true
  end
  function p.getPaperLevel() return p.paper end
  function p.getBlackInkLevel() return p.black end
  function p.getColorInkLevel() return p.color end
  function p.maxWidth() return 164 end
  function p.width(s) return fmt.width(s) end
  function p.charCount(s) return fmt.charCount(s) end
  function p.printTag(t) p.tag = t; return true end
  function p.scan() return { "scanned one", "scanned two" } end
  return p
end

-- Load printer.lua with `component` and `printerfmt` stubbed. It requires
-- kernel.process and kernel.event too; both are absent here, which is the
-- early-boot / off-box path the driver is written to tolerate.
--
-- The stub stays installed for the whole run rather than only across the
-- load: the driver resolves `component` LAZILY inside getProxy (that is
-- what makes hot-plug work), so a stub torn down after loading would be
-- gone by the time anything actually asked for hardware.
local realRequire = require
local currentFake = nil
local componentStub = {
  list = function(ctype)
    local yielded = false
    return function()
      if ctype == "openprinter" and currentFake and not yielded then
        yielded = true
        return currentFake.address
      end
    end
  end,
  proxy = function(_) return currentFake end,
}
_G.require = function(name)
  if name == "component" then return componentStub end
  if name == "printerfmt" then return fmt end
  if name == "kernel.process" or name == "kernel.event" then
    error("no such module: " .. name)
  end
  return realRequire(name)
end

local function loadDriver(fake)
  currentFake = fake
  -- A fresh chunk each time: the driver caches its proxy, and a cache
  -- carried between cases would have one fake's ink levels answering
  -- another fake's questions.
  return tryload("usr/lib/printer.lua")()
end

do
  local fake = fakePrinter()
  local P = loadDriver(fake)
  ok("driver sees the fake printer", P.available())
  test("no reason when available", nil, P.unavailableReason())

  local st = P.status()
  test("status reports paper", 64, st.paper)
  test("status reports black ink", 100, st.black)
  test("status reports colour ink", 100, st.color)
  test("status reports the page width", 164, st.maxWidth)
  ok("status detects width()", st.features.width)
  ok("status detects the absence of scanBook()", not st.features.scanBook)

  -- Prefer the component's own metrics when it has them.
  local px, src = P.width("iii")
  test("width delegates to the component", 3, px)
  test("and says so", "component", src)
end

do
  -- No printer at all: every entry point refuses cleanly instead of
  -- erroring, because "there is no printer" is the normal case on most
  -- machines and must not look like a crash.
  local P = loadDriver(nil)
  ok("no printer -> unavailable", not P.available())
  ok("no printer -> a reason", P.unavailableReason() ~= nil)
  local n, err = P.printText("hello")
  test("printText refuses", nil, n)
  ok("printText explains", err ~= nil)
  -- With no hardware to ask, width falls back to the transcribed table.
  local _, src = P.width("abc")
  test("width falls back to the estimate", "estimate", src)
end

do
  -- A job commits atomically-ish: built in memory, checked, then written.
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job("Notice")
  job:line("first"); job:line("second")
  test("one short page", 1, #job:pages())
  local c = job:cost()
  test("cost: one sheet", 1, c.paper)
  test("cost: two black lines", 2, c.black)

  local printed = job:commit()
  test("commit reports one page", 1, printed)
  test("the fake received one page", 1, #fake.printed)
  test("the title was set", "Notice", fake.printed[1].title)
  test("both lines arrived", 2, #fake.printed[1].lines)
  test("paper was consumed", 63, fake.paper)
end

do
  -- The 21st line is the mod's hard limit; the driver paginates so that
  -- limit is never reached rather than letting writeln throw.
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job("Long")
  for i = 1, 45 do job:line("line " .. i) end
  test("45 lines is 3 pages", 3, #job:pages())
  local printed, err = job:commit()
  test("all three pages print", 3, printed)
  test("no error", nil, err)
  test("the fake got three pages", 3, #fake.printed)
  ok("no page exceeded 20 lines", (function()
    for _, pg in ipairs(fake.printed) do
      if #pg.lines > 20 then return false end
    end
    return true
  end)())
end

do
  -- Pre-flight refuses a job the machine cannot finish, BEFORE any page
  -- is printed. Half a document in the output chest is the outcome this
  -- exists to prevent.
  local fake = fakePrinter({ paper = 2 })
  local P = loadDriver(fake)
  local job = P.job("Too long")
  for i = 1, 45 do job:line("line " .. i) end
  local okCheck, why = job:check()
  test("check refuses", false, okCheck)
  ok("check names the shortage", tostring(why):find("sheets") ~= nil)
  local printed = job:commit()
  test("commit refuses too", nil, printed)
  test("and printed nothing at all", 0, #fake.printed)
end

do
  -- A mid-job failure reports how many pages ALREADY came out. Without
  -- that number the operator reprints the whole document.
  local fake = fakePrinter({ failOnPage = 2 })
  local P = loadDriver(fake)
  local job = P.job("Partial")
  for i = 1, 45 do job:line("line " .. i) end
  local printed, err, partial = job:commit()
  test("commit reports failure", nil, printed)
  ok("the mod's own message survives", tostring(err):find("output slot") ~= nil)
  test("one page had already printed", 1, partial)
end

do
  -- force skips the pre-flight but not the mod's own limits.
  local fake = fakePrinter({ paper = 1 })
  local P = loadDriver(fake)
  local job = P.job("Forced")
  for i = 1, 25 do job:line("line " .. i) end
  test("check refuses on paper", false, (job:check()))
  local printed, err = job:commit({ force = true })
  test("forced past our check, stopped by the printer", nil, printed)
  ok("the printer's refusal is reported", tostring(err):find("Paper") ~= nil)
end

do
  -- Colour is opt-in per line. A black document must not touch the
  -- colour cartridge.
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job("Black only")
  job:line("plain"); job:line("also plain")
  job:commit()
  test("colour ink untouched", 100, fake.color)
  test("black ink consumed", 98, fake.black)
end

do
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job("Colour")
  job:line("red", 0xFF0000)
  job:commit()
  test("a coloured line spends colour ink", 99, fake.color)
  test("and not black", 100, fake.black)
  test("the colour reached the printer", 0xFF0000, fake.printed[1].lines[1].color)
end

do
  -- Centring is positional AFTER the colour argument, so a centred black
  -- line has to name black explicitly. That it costs colour ink is a
  -- property of the mod, and the cost report must not hide it.
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job("Centred")
  job:line("middle", nil, "center")
  job:commit()
  test("centring reached the printer", "center", fake.printed[1].lines[1].align)
  test("black was named explicitly", 0x000000, fake.printed[1].lines[1].color)
end

do
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job()
  local bad, err = job:line("x", nil, "sideways")
  test("an unknown alignment is refused", nil, bad)
  ok("and names the value", tostring(err):find("sideways") ~= nil)
  local badC, errC = job:line("x", "purple")
  test("a non-numeric colour is refused", nil, badC)
  ok("and says what it wanted", tostring(errC):find("0xRRGGBB") ~= nil)
end

do
  -- Page breaks: explicit, and never a blank sheet.
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job()
  job:line("a"); job:pageBreak(); job:line("b")
  test("an explicit break makes two pages", 2, #job:pages())
  job:pageBreak(); job:pageBreak()
  test("trailing breaks cost no paper", 2, #job:pages())
end

do
  -- A title becomes the printed item's display name, so it is capped and
  -- stripped. Neither is enforced by the mod.
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local job = P.job(string.rep("x", 200) .. "\1")
  job:line("body"); job:commit()
  test("title is capped at 64", 64, #fake.printed[1].title)
  ok("control bytes never reach the item name",
    fake.printed[1].title:find("[%z\1-\31]") == nil)
end

do
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local lines = P.scan()
  test("scan returns the page", 2, #lines)
  test("scan content", "scanned one", lines[1])
  -- scanBook is absent on older builds, and the driver says which is
  -- missing rather than throwing.
  local b, bErr = P.scanBook()
  test("scanBook refuses on this build", nil, b)
  ok("and explains", tostring(bErr):find("cannot scan books") ~= nil)
  ok("tag prints", P.tag("Rex") ~= nil)
  test("the tag reached the printer", "Rex", fake.tag)
  local t, tErr = P.tag("")
  test("an empty tag is refused", nil, t)
  ok("and says why", tostring(tErr):find("needs some text") ~= nil)
end

do
  -- printText is the one-call path: wrap to the printer's real width,
  -- paginate, print.
  local fake = fakePrinter()
  local P = loadDriver(fake)
  local body = {}
  for i = 1, 30 do body[i] = "paragraph line number " .. i end
  local printed = P.printText(table.concat(body, "\n"), { title = "Doc" })
  test("printText paginates", 2, printed)
  test("two pages reached the printer", 2, #fake.printed)
  test("printText set the title", "Doc", fake.printed[1].title)
end

do
  -- The buffer persists across programs and reboots, so every page is
  -- preceded by a clear. Without it, whatever the last program left
  -- behind prints at the top of yours.
  local fake = fakePrinter()
  fake.lines = { { text = "stale line from someone else" } }
  local P = loadDriver(fake)
  local job = P.job("Clean")
  job:line("mine")
  job:commit()
  test("the stale line did not print", 1, #fake.printed[1].lines)
  test("only our line did", "mine", fake.printed[1].lines[1].text)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
