-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: calc 2's 1-2-3 engine and operations       ║
-- ║                                                              ║
-- ║  test_calc.lua pins everything calc 1 promised (it still     ║
-- ║  passes unchanged but for the file header). This pins what   ║
-- ║  calc 2 added: 1-2-3's entry rules and syntax, the new       ║
-- ║  @functions, formats and column widths, range names, the v2  ║
-- ║  file — and that a v1 file still MEANS what it meant — and   ║
-- ║  the operations that rewrite formulas (ops.lua). Where a    ║
-- ║  result is 1-2-3's own rule rather than an obvious one, the  ║
-- ║  comment says which rule.                                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/calc/test_calc_lotus.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (want " .. tostring(expected) .. ", got " .. tostring(actual) .. ")", expected == actual)
end
local function near(name, expected, actual, tol)
  test(name .. "  (want " .. tostring(expected) .. ", got " .. tostring(actual) .. ")",
    type(actual) == "number" and math.abs(expected - actual) <= (tol or 1e-9))
end

package.path = "modules/?.lua;modules/?/init.lua;" .. package.path
local S = require("calc.sheet")
local O = require("calc.ops")

local function sheet(cells)
  local sh = S.new()
  for ref, raw in pairs(cells or {}) do
    local c, r = S.parseRef(ref)
    S.set(sh, c, r, raw)
  end
  return sh
end
local function val(sh, ref)
  local c, r = S.parseRef(ref)
  return S.evaluator(sh).get(c, r)
end
local function evalOne(formula, cells)
  local sh = sheet(cells)
  S.set(sh, 78, 512, formula)
  return S.evaluator(sh).get(78, 512)
end
local function raw(sh, ref) local c, r = S.parseRef(ref) return S.raw(sh, c, r) end

print("=== What a cell holds (1-2-3's entry rules) ===")
eq("a number", "number", (S.classify("42")))
eq("= still starts a formula", "formula", (S.classify("=A1*2")))
eq("+ starts a formula", "formula", (S.classify("+A1*2")))
eq("@ starts a formula", "formula", (S.classify("@SUM(A1..A3)")))
eq("( starts a formula", "formula", (S.classify("(A1+1)/2")))
eq("plain text is a label", "label", (S.classify("Sales")))
do
  local k, body, align = S.classify("'Left")
  test("' is a left label without its prefix", k == "label" and body == "Left" and align == "L")
  local _, _, a2 = S.classify('"Right')
  local _, _, a3 = S.classify("^Centre")
  local _, b4, a4 = S.classify("\\-")
  test("\" right, ^ centre, \\ repeat", a2 == "R" and a3 == "C" and a4 == "REP" and b4 == "-")
  local _, n = S.classify("0x10")
  eq("hex still reads as calc 1 read it", 16, n)
end

print()
print("=== 1-2-3 formula syntax ===")
do
  local cells = { A1 = "10", A2 = "20", A3 = "30", B1 = "Ann", B2 = "Bob" }
  eq("@SUM over a .. range", 60, evalOne("@SUM(A1..A3)", cells))
  eq("a single-dot range, A1.A3", 60, evalOne("@SUM(A1.A3)", cells))
  eq("the old colon range still works", 60, evalOne("=SUM(A1:A3)", cells))
  eq("a bare SUM(...) is a LABEL in 1-2-3, as typed", "SUM(A1:A3)", evalOne("SUM(A1:A3)", cells))
  eq("+A1*2 (a leading +)", 20, evalOne("+A1*2", cells))
  eq("$A$1 evaluates like A1", 10, evalOne("+$A$1", cells))
  eq("$A1 and A$1 too", 30, evalOne("+$A1+A$2", cells))
  eq("@PI takes no parentheses", math.pi, evalOne("@PI"))
  eq("#AND#", 1, evalOne("+A1>5#AND#A2>5", cells))
  eq("#OR#", 1, evalOne("+A1>50#OR#A2>5", cells))
  eq("#NOT#", 0, evalOne("#NOT#A1>5", cells))
  eq("& joins text", "Ann & Bob", evalOne('+B1&" & "&B2', cells))
  eq("& binds looser than +: 1+2&3 = 33", "33", evalOne("1+2&3"))
  test("a lone $ is still garbage", S.isErr(evalOne("1 $ 2")))
  test("LOG10 is not mistaken for column LOG, row 10", S.isErr(evalOne("+LOG10(5)")) and evalOne("+LOG10(5)").e == S.E_NAME)
  eq("1E3 in a formula is a number, not cell E3", 1001, evalOne("+1E3+1", { E3 = "99" }))
  eq("#REF! in a formula evaluates to #REF!", S.E_REF, evalOne("+#REF!+1").e)
end

print()
print("=== New @functions ===")
near("@EXP", math.exp(2), evalOne("@EXP(2)"))
near("@LN", math.log(10), evalOne("@LN(10)"))
near("@LOG is base 10", 2, evalOne("@LOG(100)"))
test("@LN of 0 is an error", S.isErr(evalOne("@LN(0)")))
near("@ATAN2(x, y), 1-2-3's argument order", math.atan(1, -1), evalOne("@ATAN2(-1,1)"))
do
  local c = { A1 = "2", A2 = "4", A3 = "4", A4 = "4", A5 = "5", A6 = "5", A7 = "7", A8 = "9" }
  near("@STD is the population figure", 2, evalOne("@STD(A1..A8)", c))
  near("@VAR", 4, evalOne("@VAR(A1..A8)", c))
end
eq("@CHOOSE counts from 0", "b", evalOne('@CHOOSE(1,"a","b","c")'))
test("@CHOOSE past the end is an error", S.isErr(evalOne('@CHOOSE(3,"a","b","c")')))
do
  local tbl = { A1 = "0", B1 = "'none", A2 = "100", B2 = "'bronze", A3 = "500", B3 = "'silver", A4 = "1000", B4 = "'gold" }
  eq("@VLOOKUP finds the last key not over x", "silver", evalOne("@VLOOKUP(750,A1..B4,1)", tbl))
  eq("@VLOOKUP exactly on a key", "gold", evalOne("@VLOOKUP(1000,A1..B4,1)", tbl))
  eq("offset 0 is the key itself", 500, evalOne("@VLOOKUP(750,A1..B4,0)", tbl))
  eq("below the first key: #N/A", S.E_NA, evalOne("@VLOOKUP(-5,A1..B4,1)", tbl).e)
  local h = { A1 = "1", B1 = "2", C1 = "3", A2 = "10", B2 = "20", C2 = "30" }
  eq("@HLOOKUP", 20, evalOne("@HLOOKUP(2,A1..C2,1)", h))
end
near("@PMT(principal, rate, term)", 10000 * 0.01 / (1 - 1.01 ^ -12), evalOne("@PMT(10000,0.01,12)"))
near("@PV(payment, rate, term)", 100 * (1 - 1.05 ^ -10) / 0.05, evalOne("@PV(100,0.05,10)"))
near("@FV(payment, rate, term)", 100 * (1.05 ^ 10 - 1) / 0.05, evalOne("@FV(100,0.05,10)"))
near("@NPV(rate, range)", 100 / 1.1 + 200 / 1.21, evalOne("@NPV(0.1,A1..A2)", { A1 = "100", A2 = "200" }))
eq("@ISERR sees an error", 1, evalOne("@ISERR(1/0)"))
eq("@ISERR of a number", 0, evalOne("@ISERR(5)"))
eq("@NA", S.E_NA, evalOne("@NA").e)
eq("@ISSTRING", 1, evalOne('@ISSTRING("x")'))
eq("@MID counts from 0", "ell", evalOne('@MID("hello",1,3)'))
eq("@FIND counts from 0", 2, evalOne('@FIND("l","hello")'))
eq("@LEFT", "he", evalOne('@LEFT("hello",2)'))
eq("@RIGHT", "lo", evalOne('@RIGHT("hello",2)'))
eq("@PROPER", "Hello World", evalOne('@PROPER("hELLO wORLD")'))
eq("@TRIM", "a b", evalOne('@TRIM("  a   b ")'))
eq("@REPEAT", "-=-=", evalOne('@REPEAT("-=",2)'))
test("@REPEAT refuses to build a huge string", S.isErr(evalOne('@REPEAT("x",100000)')))
eq("@STRING", "3.14", evalOne("@STRING(3.14159,2)"))
eq("@VALUE", 42.5, evalOne('@VALUE(" 42.5 ")'))
eq("@EXACT is case-sensitive", 0, evalOne('@EXACT("a","A")'))
eq("@TRUE", 1, evalOne("@TRUE"))

print()
print("=== Range names ===")
do
  local sh = sheet({ A1 = "1", A2 = "2", A3 = "3" })
  sh.names.SALES = { 1, 1, 1, 3 }
  sh.names.FIRST = { 1, 1, 1, 1 }
  S.set(sh, 2, 1, "@SUM(SALES)")
  S.set(sh, 2, 2, "+FIRST*10")
  S.set(sh, 2, 3, "+NOSUCH")
  eq("@SUM over a named range", 6, val(sh, "B1"))
  eq("a one-cell name reads as its cell", 10, val(sh, "B2"))
  eq("an unknown name is #NAME?", S.E_NAME, val(sh, "B3").e)
  test("a name may not look like a cell", not O.validName("Q1") and O.validName("Q1_TOTAL"))
  test("nor like a function", not O.validName("SUM"))
end

print()
print("=== Formats and widths ===")
eq("Fixed 2", "1234.50", S.formatNumber(1234.5, "F2"))
eq("Comma 2", "1,234.50", S.formatNumber(1234.5, ",2"))
eq("Currency 0", "$1,235", S.formatNumber(1234.5, "C0"))
eq("a negative amount is bracketed", "($1,234.50)", S.formatNumber(-1234.5, "C2"))
eq("Percent 1", "12.5%", S.formatNumber(0.125, "P1"))
eq("Scientific 2", "1.23E+03", S.formatNumber(1234.5, "S2"))
eq("+/- draws a bar", "+++", S.formatNumber(3.7, "+"))
eq("+/- negative", "--", S.formatNumber(-2, "+"))
eq("too wide for the column: asterisks", "*****", S.formatNumber(123456.789, "F2", 5))
eq("General shortens to fit", "3.142", S.formatNumber(math.pi, "G", 5))
do
  local sh = sheet({ A1 = "1234.5", B1 = "^Mid", C1 = "\\=", D1 = "+A1*2" })
  sh.fmt[S._key(1, 1)] = "C2"
  local t, a = S.cellText(sh, S.evaluator(sh), 1, 1, 12)
  test("a currency cell, right-aligned", t == "$1,234.50" and a == "R")
  local t2, a2 = S.cellText(sh, S.evaluator(sh), 2, 1, 9)
  test("a ^ label is centred", t2 == "Mid" and a2 == "C")
  eq("a \\ label fills the column", "=========", (S.cellText(sh, S.evaluator(sh), 3, 1, 9)))
  sh.fmt[S._key(4, 1)] = "T"
  eq("Text format shows the formula", "+A1*2", (S.cellText(sh, S.evaluator(sh), 4, 1, 9)))
  sh.fmt[S._key(4, 1)] = "H"
  eq("Hidden shows nothing", "", (S.cellText(sh, S.evaluator(sh), 4, 1, 9)))
  sh.gprefix = '"'
  S.set(sh, 5, 1, "plain")
  local _, a5 = S.cellText(sh, S.evaluator(sh), 5, 1, 9)
  eq("an unprefixed label takes the sheet's default prefix", "R", a5)
end

print()
print("=== The v2 file, and v1 files keep their meaning ===")
do
  local sh = sheet({ A1 = "10", B1 = "@SUM(A1..A3)", A2 = "'(note)" })
  sh.fmt[S._key(1, 1)] = "F2"
  sh.colw[2] = 14
  sh.gfmt = ",0"
  sh.names.TOTAL = { 2, 1, 2, 1 }
  sh.recalc = "manual"
  sh.graph.type = "bar"; sh.graph.a = "A1..A3"
  local back = S.deserialize(S.serialize(sh))
  eq("cell round-trips", "@SUM(A1..A3)", raw(back, "B1"))
  eq("format round-trips", "F2", back.fmt[S._key(1, 1)])
  eq("width round-trips", 14, back.colw[2])
  eq("global format round-trips", ",0", back.gfmt)
  test("a name round-trips", back.names.TOTAL and back.names.TOTAL[1] == 2)
  eq("recalc mode round-trips", "manual", back.recalc)
  eq("graph settings round-trip", "A1..A3", back.graph.a)
  eq("nothing skipped", 0, back.skipped)
  local hostile = S.deserialize("TOSCALC2\nA1\t5\n#fmt A1 os.exit\n#width B 9999\n#name A1 A1..A2\n#junk x")
  test("a bad format, a silly width and a name shaped like a cell are refused",
    hostile.fmt[S._key(1, 1)] == nil and hostile.colw[2] == S.MAX_WIDTH and hostile.names.A1 == nil)
end
do
  -- In calc 1, "(note)" and "+1 more" were TEXT. A v1 file must not turn
  -- them into broken formulas under the 1-2-3 rules.
  local v1 = "TOSCALC1\nA1\t(note)\nA2\t+1 more\nA3\t=A4*2\nA4\t21\nA5\t5 apples"
  local sh = S.deserialize(v1)
  eq("v1 text that looks like a formula stays text", "(note)", val(sh, "A1"))
  eq("...all of it", "+1 more", val(sh, "A2"))
  eq("v1 formulas still compute", 42, val(sh, "A3"))
  eq("v1 '5 apples' stays a label", "5 apples", val(sh, "A5"))
end
do
  local sh = S.new()
  local n = S.fromCSV(sh, 'Name,Qty,Note\n"Smith, J",12,=1+1\nLee,3.5,"say ""hi"""\n')
  eq("CSV import set all 9 cells", 9, n)
  eq("a quoted comma stays in its field", "Smith, J", val(sh, "A2"))
  eq("a number arrives as a number", 3.5, val(sh, "B3"))
  eq("an =formula in a CSV arrives as TEXT", "=1+1", val(sh, "C2"))
  eq("doubled quotes", 'say "hi"', val(sh, "C3"))
end

print()
print("=== Copy: relative moves, $ stays (ops.lua) ===")
eq("shift a relative ref", "+B2*2", O.shift("+A1*2", 1, 1))
eq("$A$1 does not move", "+$A$1*B2", O.shift("+$A$1*A1", 1, 1))
eq("mixed: $A1 keeps its column", "+$A2+B$1", O.shift("+$A1+A$1", 1, 1))
eq("a range moves both ends", "@SUM(B1..B3)", O.shift("@SUM(A1..A3)", 1, 0))
eq("spacing and @ survive", "@SUM( B2 .. B4 ) + 1", O.shift("@SUM( A1 .. A3 ) + 1", 1, 1):gsub("B2 %.%. B4", "B2 .. B4"))
eq("off the sheet becomes #REF!", "+#REF!", O.shift("+A1", -1, 0))
eq("text inside quotes is never a reference", '+"A1"&B1', O.shift('+"A1"&A1', 1, 0))
eq("1E5 is not cell E5", "+1E5+B1", O.shift("+1E5+A1", 1, 0))
eq("labels are untouched", "'A1 total", O.shift("'A1 total", 3, 3))
do
  local sh = sheet({ A1 = "1", A2 = "2", B1 = "+A1*10" })
  O.copy(sh, 2, 1, 2, 1, 2, 2, 2, 4)        -- B1 -> B2..B4
  eq("one cell copied down a column", "+A2*10", raw(sh, "B2"))
  eq("...each one relative", "+A4*10", raw(sh, "B4"))
  eq("and it computes", 20, val(sh, "B2"))
  local sh2 = sheet({ A1 = "1", B1 = "2", C1 = "@SUM(A1..B1)" })
  sh2.fmt[S._key(3, 1)] = "F2"
  O.copy(sh2, 1, 1, 3, 1, 1, 2, 1, 3)       -- the row A1..C1 to rows 2 and 3
  eq("a row copied to each destination row", "@SUM(A3..B3)", raw(sh2, "C3"))
  eq("formats travel", "F2", sh2.fmt[S._key(3, 3)])
end

print()
print("=== Move ===")
do
  local sh = sheet({ A1 = "5", A2 = "+A1*2", C1 = "+A1+A2", D1 = "+$A$1" })
  O.move(sh, 1, 1, 1, 2, 2, 5)              -- A1..A2 -> B5..B6
  eq("the moved cells arrive", "5", raw(sh, "B5"))
  eq("a formula inside the block follows its partner", "+B5*2", raw(sh, "B6"))
  eq("a formula outside follows the moved cells", "+B5+B6", raw(sh, "C1"))
  eq("...even an absolute one", "+$B$5", raw(sh, "D1"))
  eq("and still computes", 15, val(sh, "C1"))
  eq("the source is empty", "", raw(sh, "A1"))
  local sh2 = sheet({ A1 = "1", B1 = "2", C1 = "+B1" })
  O.move(sh2, 1, 1, 1, 1, 2, 1)             -- A1 onto B1
  eq("a reference to an overwritten cell is #REF!", "+#REF!", raw(sh2, "C1"))
end

print()
print("=== Insert and delete ===")
do
  local sh = sheet({ A1 = "1", A2 = "2", A3 = "3", A5 = "@SUM(A1..A3)", B1 = "+A3" })
  O.insertRows(sh, 2, 1)
  eq("rows from 2 move down", "2", raw(sh, "A3"))
  eq("a range spanning the insert grows", "@SUM(A1..A4)", raw(sh, "A6"))
  eq("a reference past it follows", "+A4", raw(sh, "B1"))
  eq("still the same total", 6, val(sh, "A6"))
  O.deleteRows(sh, 2, 1)
  eq("delete undoes it", "@SUM(A1..A3)", raw(sh, "A5"))
  O.deleteRows(sh, 3, 1)                      -- A3 goes
  eq("a reference into deleted rows is #REF!", "+#REF!", raw(sh, "B1"))
  eq("a range losing its end shrinks", "@SUM(A1..A2)", raw(sh, "A4"))
  local sh2 = sheet({ A1 = "1", B1 = "2", C1 = "+A1+B1" })
  sh2.colw[2] = 15
  O.insertCols(sh2, 2, 2)
  eq("columns move right", "+A1+D1", raw(sh2, "E1"))
  eq("column widths move with them", 15, sh2.colw[4])
  sh2.names.R = { 1, 1, 4, 1 }
  O.deleteCols(sh2, 1, 1)
  test("a name shrinks with its range", sh2.names.R[1] == 1 and sh2.names.R[3] == 3)
end

print()
print("=== Sort, fill, values, labels ===")
do
  local sh = sheet({ A1 = "Pear", B1 = "3", C1 = "+B1*2",
                     A2 = "apple", B2 = "1", C2 = "+B2*2",
                     A3 = "10", B3 = "2", C3 = "+B3*2" })
  O.sort(sh, 1, 1, 3, 3, 1, true)
  eq("numbers sort before labels", "10", raw(sh, "A1"))
  eq("labels alphabetically, case aside", "apple", raw(sh, "A2"))
  eq("a moved row's formula moves like a copy", "+B2*2", raw(sh, "C2"))
  eq("and points at its own row's value", 2, val(sh, "C2"))
  O.sort(sh, 1, 1, 3, 3, 2, false)
  eq("descending by a second column", "3", raw(sh, "B1"))
  local f = S.new()
  eq("fill writes until stop", 4, O.fill(f, 1, 1, 1, 10, 0, 5, 15))
  eq("...0, 5, 10, 15", "15", raw(f, "A4"))
  local v = sheet({ A1 = "2", A2 = "+A1*21" })
  O.values(v, 1, 2, 1, 2, 2, 2)
  eq("/Range Value writes the number, not the formula", "42", raw(v, "B2"))
  local l = sheet({ A1 = "Left", A2 = "5" })
  O.label(l, 1, 1, 1, 2, "^")
  eq("/Range Label re-prefixes labels", "^Left", raw(l, "A1"))
  eq("...and leaves numbers alone", "5", raw(l, "A2"))
end

print()
print("=== Print and sort settings live in the file ===")
do
  local sh = sheet({ A1 = "5" })
  sh.print.range = "A1..C9"; sh.print.header = "Budget|Q3|Page #"; sh.print.formulas = true
  sh.sort.range = "A2..C9"; sh.sort.k1 = "B2"; sh.sort.o1 = "D"
  local back = S.deserialize(S.serialize(sh))
  test("print settings round-trip", back.print.range == "A1..C9" and back.print.header == "Budget|Q3|Page #"
    and back.print.formulas == true)
  test("sort settings round-trip", back.sort.k1 == "B2" and back.sort.o1 == "D")
  local bad = S.deserialize("TOSCALC2\n#print range nope\n#sort o1 X\n#print evil 1")
  test("a bad range, order or key is refused", bad.print.range == nil and bad.sort.o1 == nil and bad.skipped == 3)
end

print()
print("=== Page layout (print.lua) ===")
do
  local P = require("calc.print")
  local fmt = dofile("modules/printer/usr/lib/printerfmt.lua")
  eq("header parts: | splits, # is the page", "Page 3", select(3, P.headerParts("Budget|Q3|Page #", 3)))
  local sh = sheet({ A1 = "'Item", B1 = '"Qty', A2 = "'Bolts", B2 = "12", A3 = "'Nuts", B3 = "1250" })
  local ctx = S.evaluator(sh)
  local file = P.pages(sh, ctx, 1, 1, 2, 3, { target = "file" })
  eq("a file is one page", 1, #file)
  eq("columns line up by character", "Bolts            12", file[1][2])
  eq("a right label lines up with the numbers", "Item            Qty", file[1][1])
  local paper = P.pages(sh, ctx, 1, 1, 2, 3, { target = "printer", measure = fmt.width, maxWidth = fmt.MAX_WIDTH })
  local okW = true
  for _, l in ipairs(paper[1]) do if fmt.width(l) > fmt.MAX_WIDTH then okW = false end end
  test("every printed line fits the paper", okW)
  -- The number's RIGHT edge lands at the same pixel on every row.
  local function rightEdge(line) return fmt.width(line) end
  test("numbers right-align by the pixel (within a space)",
    math.abs(rightEdge(paper[1][2]) - rightEdge(paper[1][3])) <= P.SPACE_PX)
  -- 30 rows of 6 columns: wider than a page and longer than one.
  local big = S.new()
  for r = 1, 30 do for c = 1, 6 do S.set(big, c, r, tostring(r * c)) end end
  local pages = P.pages(big, S.evaluator(big), 1, 1, 6, 30,
    { target = "printer", measure = fmt.width, maxWidth = fmt.MAX_WIDTH, header = "H", footer = "F" })
  -- 6 columns of 45 px with a 3 px gap: 3 per 164 px band, so 2 bands;
  -- 20 lines less 2 header and 2 footer is 16 rows a page, so 2 pages a band.
  eq("down, then across: 2 bands of 2 pages", 4, #pages)
  test("no page passes 20 lines", #pages[1] <= 20 and #pages[4] <= 20)
  local doc = P.toWrite({ { ".hidden", "x" }, { "y" } }, "T")
  test("a write document: title, .page between, a leading dot doubled",
    doc:find("^%.title T\n") and doc:find("\n%.%.hidden\n") and doc:find("\n%.page\n"))
  local listing = P.pages(sh, ctx, 1, 1, 2, 3, { target = "file", formulas = true })
  eq("Cell-Formulas lists what is in each cell", "B2: 12", listing[1][4])
end

print()
print("=== Graph (graph.lua) ===")
do
  local G = require("calc.graph")
  eq("niceCeil 37 -> 50", 50, G.niceCeil(37))
  eq("niceCeil 101 -> 200", 200, G.niceCeil(101))
  local sh = sheet({ A1 = "'Q1", A2 = "'Q2", A3 = "'Q3", B1 = "10", B2 = "40", B3 = "25" })
  sh.graph = { type = "bar", x = "A1..A3", a = "B1..B3", title1 = "Sales" }
  local d = G.collect(sh, S.evaluator(sh))
  local rows, marks = G.render(d, 40, 14)
  test("a bar graph renders", rows ~= nil and #rows == 14)
  test("the title is centred on the first line", rows and rows[1]:find("Sales", 1, true) ~= nil)
  local tallest, tallestX = 0, nil
  if rows then
    -- Count each column's bar height: the 40 must be the tallest.
    local heights = {}
    for y = 1, 14 do
      for x = 1, 40 do if marks[y][x] == "a" then heights[x] = (heights[x] or 0) + 1 end end
    end
    for x, h in pairs(heights) do if h > tallest then tallest, tallestX = h, x end end
  end
  test("the Q2 bar (40) is the tallest", tallestX and rows[13]:sub(tallestX, tallestX + 1) == "Q2"
    or (tallestX and rows[13]:find("Q2", 1, true)))
  local none = G.collect(S.new(), S.evaluator(S.new()))
  test("no data range: a reason, not a crash", select(2, G.render(none, 40, 14)) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All tests passed.")
