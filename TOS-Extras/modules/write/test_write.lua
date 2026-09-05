-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: write — the document model                         ║
-- ║                                                            ║
-- ║  doc.lua is pure, so all of it tests off-box. The point of ║
-- ║  most of these assertions is the SOURCE-LINE mapping: the  ║
-- ║  editor's page ruler is only as honest as doc.locate, and  ║
-- ║  the failure mode is silent (the ruler drifts, the         ║
-- ║  operator trusts it, the page break lands elsewhere).      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua modules/write/test_write.lua   (from TOS-Extras root)

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

local here = (arg and arg[0]) or "modules/write/test_write.lua"
local base = here:gsub("[^/\\]*$", "")
local function findChunk(rel, roots)
  for _, root in ipairs(roots) do
    local chunk = loadfile(root .. rel)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

-- doc.lua requires printerfmt, which ships in the PRINTER package — the
-- dependency this package declares. Load it from there and pre-register
-- it, exactly as the installed layout would (/usr/lib/printerfmt.lua).
local fmt = findChunk("usr/lib/printerfmt.lua", {
  base .. "../printer/", "modules/printer/", "TOS-Extras/modules/printer/" })()
package.loaded["printerfmt"] = fmt

local D = findChunk("doc.lua", {
  base, "modules/write/", "TOS-Extras/modules/write/" })()

print("=== write (word processor) Tests ===")
print()

-- One pixel per character, so the arithmetic in these tests is readable.
local one = function(s) return #s end

-- ══════════════════════════════════════════════════════════════════════
-- Parsing: dot commands
-- ══════════════════════════════════════════════════════════════════════
do
  local p = D.parse(".title My Report\nHello world")
  test("title is lifted out", "My Report", p.title)
  test("the .title line produces no block", 1, #p.blocks)
  test("the body survives", "Hello world", p.blocks[1].text)
  -- Source-line numbers must survive the directive, or the ruler drifts
  -- by one for the whole rest of the document.
  test("body block remembers it was source line 2", 2, p.blocks[1].srcLine)
end

do
  local p = D.parse("plain\n.center\nmiddle\n.left\nback")
  test("three text blocks", 3, #p.blocks)
  test("before .center is left", "left", p.blocks[1].align)
  test(".center applies from there on", "center", p.blocks[2].align)
  test(".left turns it back off", "left", p.blocks[3].align)
  test("source lines skip both directives", 3, p.blocks[2].srcLine)
  test("and the second one too", 5, p.blocks[3].srcLine)
  -- British spelling accepted; a word processor arguing about it would
  -- be picking a fight it cannot win.
  test(".centre is the same command", "center", D.parse(".centre\nx").blocks[1].align)
end

do
  local p = D.parse(".color 0xFF0000\nred\n.color off\nblack")
  test("colour applies", 0xFF0000, p.blocks[1].color)
  test(".color off clears it", nil, p.blocks[2].color)
  test(".colour is the same command", 0x00FF00, D.parse(".colour 0x00FF00\nx").blocks[1].color)
  test("a bare .color clears too", nil, D.parse(".color 0xFF0000\n.color\nx").blocks[1].color)
end

do
  -- A malformed directive is a WARNING and the line is kept as text. A
  -- word processor that refuses to open a document over a typo on line
  -- 40 has failed at its one job.
  local p = D.parse(".color banana\ntext")
  test("a bad colour warns", 1, #p.warnings)
  test("and names the line", 1, p.warnings[1].line)
  ok("and explains", tostring(p.warnings[1].text):find("not a colour") ~= nil)
  test("the document still parses", 1, #p.blocks)

  local u = D.parse(".wibble\ntext")
  test("an unknown command warns", 1, #u.warnings)
  test("and the line is kept as literal text", ".wibble", u.blocks[1].text)
  test("so nothing is silently lost", 2, #u.blocks)
end

do
  -- Escaping, so a document CAN start a line with a period.
  local p = D.parse("..title is not a command")
  test("'..' escapes to one dot", ".title is not a command", p.blocks[1].text)
  test("no title was set", nil, p.title)
  test("and no warning was raised", 0, #p.warnings)
end

do
  local p = D.parse("a\n.page\nb")
  test("a break is its own block", 3, #p.blocks)
  ok("marked as a break", p.blocks[2].page)
  test("and carries its source line", 2, p.blocks[2].srcLine)
end

-- ══════════════════════════════════════════════════════════════════════
-- Layout
-- ══════════════════════════════════════════════════════════════════════
do
  local src = {}
  for i = 1, 25 do src[i] = "line " .. i end
  local p = D.parse(table.concat(src, "\n"))
  local pages = D.layout(p, { measure = one, maxWidth = 100 })
  test("25 lines is 2 sheets", 2, #pages)
  test("the first sheet is full", 20, #pages[1])
  test("the second holds the rest", 5, #pages[2])
  test("lines carry their alignment", "left", pages[1][1].align)
end

do
  local p = D.parse("a\n.page\nb")
  local pages = D.layout(p, { measure = one })
  test(".page starts a new sheet", 2, #pages)
  test("first sheet content", "a", pages[1][1].text)
  test("second sheet content", "b", pages[2][1].text)
end

do
  -- A break with nothing before it must not cost a blank sheet.
  local pages = D.layout(D.parse(".page\n.page\na"), { measure = one })
  test("leading breaks cost no paper", 1, #pages)
end

do
  -- Long lines wrap against the printer's real pixel budget.
  local p = D.parse(string.rep("word ", 60))
  local pages = D.layout(p, { measure = one, maxWidth = 20 })
  ok("a long paragraph wraps to several lines", #pages[1] > 1)
  for _, entry in ipairs(pages[1]) do
    ok("no wrapped line exceeds the budget", #entry.text <= 20)
  end
end

do
  test("an empty document is one empty sheet", 1, #D.layout(D.parse(""), {}))
end

-- ══════════════════════════════════════════════════════════════════════
-- The page ruler — where does the cursor print?
-- ══════════════════════════════════════════════════════════════════════
do
  local src = {}
  for i = 1, 25 do src[i] = "line " .. i end
  local p = D.parse(table.concat(src, "\n"))
  local pages = D.layout(p, { measure = one, maxWidth = 100 })

  local pg, ln = D.locate(pages, 1)
  test("source line 1 is on sheet 1", 1, pg)
  test("at line 1 of it", 1, ln)

  pg, ln = D.locate(pages, 20)
  test("source line 20 is on sheet 1", 1, pg)
  test("at line 20", 20, ln)

  pg, ln = D.locate(pages, 21)
  test("source line 21 spills to sheet 2", 2, pg)
  test("at line 1 of it", 1, ln)
end

do
  -- THE REGRESSION THIS FILE EXISTS FOR: directives produce no printed
  -- line, so a ruler that indexed pages by cursor row would drift by one
  -- for everything after the first dot command. Here the title pushes
  -- every body line down by one SOURCE line without moving it on the
  -- PAGE, and the mapping has to survive that.
  local src = { ".title Report" }
  for i = 1, 25 do src[#src + 1] = "line " .. i end
  local p = D.parse(table.concat(src, "\n"))
  local pages = D.layout(p, { measure = one, maxWidth = 100 })

  test("body still fits on 2 sheets", 2, #pages)
  local pg, ln = D.locate(pages, 2)      -- source line 2 = first body line
  test("first body line is sheet 1 line 1", 1, pg)
  test("not offset by the directive", 1, ln)

  local pg21 = D.locate(pages, 21)       -- 20th body line
  test("the 20th body line is still on sheet 1", 1, pg21)
  local pg22 = D.locate(pages, 22)       -- 21st body line
  test("the 21st spills to sheet 2", 2, pg22)
end

do
  -- A cursor sitting ON a directive prints nothing, so locate returns
  -- nothing — but the ruler still needs a page to show, or the indicator
  -- blinks out exactly while you are formatting.
  local p = D.parse("a\nb\n.center\nc")
  local pages = D.layout(p, { measure = one })
  test("a directive line locates nowhere", nil, (D.locate(pages, 3)))
  test("but pageFor falls back to the previous printed line", 1, D.pageFor(pages, 3))
  test("pageFor on a printed line is exact", 1, D.pageFor(pages, 4))
end

do
  -- A wrapped source line occupies several printed lines; locate reports
  -- the FIRST, which is what "where does my cursor print" means.
  local p = D.parse("short\n" .. string.rep("x ", 40))
  local pages = D.layout(p, { measure = one, maxWidth = 10 })
  local _, ln = D.locate(pages, 2)
  test("a wrapped line reports its first printed row", 2, ln)
end

-- ══════════════════════════════════════════════════════════════════════
-- Cost and statistics
-- ══════════════════════════════════════════════════════════════════════
do
  local p = D.parse("one two three\nfour five")
  local pages = D.layout(p, { measure = one, maxWidth = 100 })
  local s = D.stats(p, pages)
  test("words are counted", 5, s.words)
  test("printed lines are counted", 2, s.lines)
  test("sheets are counted", 1, s.pages)
  -- Directives are not prose and must not inflate the word count.
  local p2 = D.parse(".title A Long Title Here\n.center\none two")
  test("directives are not words", 2, D.stats(p2, D.layout(p2, {})).words)
end

do
  -- Colour is charged per LINE, and the editor's rail reports it
  -- separately so a .color left switched on cannot quietly drain a
  -- cartridge.
  local p = D.parse(".color 0xFF0000\nred one\nred two\n.color off\nblack")
  local pages = D.layout(p, { measure = one, maxWidth = 100 })
  local c = D.cost(pages, 1)
  test("one sheet", 1, c.paper)
  test("two coloured lines cost colour ink", 2, c.color)
  test("the uncoloured one costs black", 1, c.black)
  test("copies multiply the cost", 3, D.cost(pages, 3).paper)
end

-- ══════════════════════════════════════════════════════════════════════
-- The buffer — what the editor holds
-- ══════════════════════════════════════════════════════════════════════
do
  local b = D.toBuffer("a\nb\nc")
  test("three lines", 3, #b)
  test("first", "a", b[1])
  -- An empty file opens as ONE empty line. A buffer with no lines has no
  -- cursor position, and every editor that allows it grows a special
  -- case for the empty document.
  test("an empty file is one empty line", 1, #D.toBuffer(""))
  test("that line is empty", "", D.toBuffer("")[1])
  test("nil is the same", 1, #D.toBuffer(nil))
end

do
  -- Round trip: the buffer IS the source, so saving is a join and there
  -- is no lossy model in between.
  local text = ".title T\n.center\nhello\n.left\nworld"
  test("serialize(toBuffer(x)) == x", text, D.serialize(D.toBuffer(text)))
end

do
  -- The page constants come from the printer package, not a second copy
  -- here. Two definitions of "how tall is a page" is one too many.
  test("page height comes from printerfmt", fmt.MAX_LINES, D.MAX_LINES)
  test("page width comes from printerfmt", fmt.MAX_WIDTH, D.MAX_WIDTH)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
