-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: calc/sheet.lua (model + formula engine)    ║
-- ║                                                              ║
-- ║  The engine is pure, so it tests off-box with no stubs.      ║
-- ║  Covers addressing, the tokenizer/parser (precedence,        ║
-- ║  associativity, unary, strings), evaluation, every shipped   ║
-- ║  function, error propagation, CYCLE detection, and the       ║
-- ║  save/load round-trip — including the security property      ║
-- ║  that matters most: a formula is DATA, never code.           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/calc/test_calc.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "modules/?.lua;modules/?/init.lua;" .. package.path
local S = require("calc.sheet")

-- Evaluate a one-off formula against a sheet.
local function evalIn(sh, formula)
  local tmpC, tmpR = S.MAX_COLS, S.MAX_ROWS      -- park it out of the way
  S.set(sh, tmpC, tmpR, "=" .. formula)
  local ctx = S.evaluator(sh)
  local v = ctx.get(tmpC, tmpR)
  S.set(sh, tmpC, tmpR, nil)
  return v
end
local function evalOne(formula) return evalIn(S.new(), formula) end
local function dispOne(formula)
  local sh = S.new()
  S.set(sh, 1, 1, "=" .. formula)
  local ctx = S.evaluator(sh)
  return S.display(sh, ctx, 1, 1)
end

print("=== calc/sheet Tests ===")
print()

-- ── Addressing ─────────────────────────────────────────────────────
eq("col 1 is A", "A", S.colName(1))
eq("col 26 is Z", "Z", S.colName(26))
eq("col 27 is AA", "AA", S.colName(27))
eq("col 52 is AZ", "AZ", S.colName(52))
eq("A -> 1", 1, S.colIndex("A"))
eq("AA -> 27", 27, S.colIndex("AA"))
eq("round-trips", 40, S.colIndex(S.colName(40)))
do
  local c, r = S.parseRef("B3")
  eq("B3 column", 2, c); eq("B3 row", 3, r)
  local c2, r2 = S.parseRef("AA10")
  eq("AA10 column", 27, c2); eq("AA10 row", 10, r2)
  eq("junk is not a ref", nil, (S.parseRef("hello")))
  eq("a bare number is not a ref", nil, (S.parseRef("12")))
  eq("out-of-range row refused", nil, (S.parseRef("A99999")))
end

-- ── Literal cells ──────────────────────────────────────────────────
do
  local sh = S.new()
  S.set(sh, 1, 1, "42")
  S.set(sh, 2, 1, "hello")
  local ctx = S.evaluator(sh)
  eq("numeric text becomes a number", 42, ctx.get(1, 1))
  eq("non-numeric stays text", "hello", ctx.get(2, 1))
  eq("empty cell is nil", nil, ctx.get(5, 5))
  eq("number displays without decimals", "42", S.display(sh, ctx, 1, 1))
  eq("clearing removes the cell", "", (S.set(sh, 1, 1, nil) and S.raw(sh, 1, 1)))
end

-- ── Arithmetic + precedence ────────────────────────────────────────
eq("addition", 3, evalOne("1+2"))
eq("multiplication binds tighter", 7, evalOne("1+2*3"))
eq("parens override", 9, evalOne("(1+2)*3"))
eq("subtraction is left-assoc", 0, evalOne("10-5-5"))
eq("division", 2.5, evalOne("5/2"))
eq("modulo", 1, evalOne("7%3"))
eq("power is right-assoc", 512, evalOne("2^3^2"))
eq("unary minus", -5, evalOne("-5"))
eq("unary binds under power", -9, evalOne("-3^2"))
eq("double negative", 5, evalOne("--5"))
eq("scientific notation", 1500, evalOne("1.5e3"))
eq("decimal", 0.5, evalOne("0.5"))

-- ── Comparisons ────────────────────────────────────────────────────
eq("less than true", 1, evalOne("1<2"))
eq("less than false", 0, evalOne("2<1"))
eq("equality", 1, evalOne("2=2"))
eq("inequality", 1, evalOne("2<>3"))
eq("gte", 1, evalOne("3>=3"))
eq("text equality", 1, evalOne('"yes"="yes"'))
eq("text inequality", 1, evalOne('"yes"<>"no"'))

-- ── Strings ────────────────────────────────────────────────────────
eq("string literal", "hi", evalOne('"hi"'))
eq("escaped quote", 'a"b', evalOne('"a""b"'))
eq("CONCAT joins", "abc", evalOne('CONCAT("a","b","c")'))
eq("LEN counts", 5, evalOne('LEN("hello")'))
eq("UPPER", "ABC", evalOne('UPPER("abc")'))
eq("LOWER", "abc", evalOne('LOWER("ABC")'))
test("adding text is an error, not silent concat",
  S.isErr(evalOne('"a"+"b"')))

-- ── References + ranges ────────────────────────────────────────────
do
  local sh = S.new()
  S.set(sh, 1, 1, "10"); S.set(sh, 1, 2, "20"); S.set(sh, 1, 3, "30")
  S.set(sh, 2, 1, "=A1*2")
  local ctx = S.evaluator(sh)
  eq("a reference resolves", 20, ctx.get(2, 1))
  eq("SUM over a range", 60, evalIn(sh, "SUM(A1:A3)"))
  eq("AVERAGE over a range", 20, evalIn(sh, "AVERAGE(A1:A3)"))
  eq("MIN", 10, evalIn(sh, "MIN(A1:A3)"))
  eq("MAX", 30, evalIn(sh, "MAX(A1:A3)"))
  eq("COUNT", 3, evalIn(sh, "COUNT(A1:A3)"))
  eq("mixed args and ranges", 65, evalIn(sh, "SUM(A1:A3,5)"))
  eq("a reversed range still works", 60, evalIn(sh, "SUM(A3:A1)"))

  -- Text inside a range is skipped, not an error: label rows are normal.
  S.set(sh, 1, 4, "total")
  eq("text in a range is skipped by SUM", 60, evalIn(sh, "SUM(A1:A4)"))
  eq("...and by COUNT", 3, evalIn(sh, "COUNT(A1:A4)"))

  eq("an empty cell reads as 0 in arithmetic", 10, evalIn(sh, "A1+Z9"))
  test("a bare range is not a value", S.isErr(evalIn(sh, "A1:A3")))
end

-- ── Functions ──────────────────────────────────────────────────────
eq("ABS", 5, evalOne("ABS(-5)"))
eq("SQRT", 4, evalOne("SQRT(16)"))
test("SQRT of a negative errors", S.isErr(evalOne("SQRT(-1)")))
eq("FLOOR", 2, evalOne("FLOOR(2.7)"))
eq("CEIL", 3, evalOne("CEIL(2.1)"))
eq("INT truncates down", 2, evalOne("INT(2.9)"))
eq("POWER", 8, evalOne("POWER(2,3)"))
eq("MOD", 1, evalOne("MOD(7,3)"))
test("MOD by zero errors", S.isErr(evalOne("MOD(7,0)")))
eq("ROUND to integer", 3, evalOne("ROUND(2.5)"))
eq("ROUND half away from zero (not banker's)", 3, evalOne("ROUND(2.5)"))
eq("ROUND negative half away from zero", -3, evalOne("ROUND(-2.5)"))
eq("ROUND to decimals", 3.14, evalOne("ROUND(3.14159,2)"))
eq("IF true branch", 10, evalOne("IF(1,10,20)"))
eq("IF false branch", 20, evalOne("IF(0,10,20)"))
eq("IF from a comparison", 1, evalOne("IF(2>1,1,0)"))
eq("IF defaults the else to 0", 0, evalOne("IF(0,5)"))
eq("AND", 1, evalOne("AND(1,1)"))
eq("AND with a false", 0, evalOne("AND(1,0)"))
eq("OR", 1, evalOne("OR(0,1)"))
eq("NOT", 1, evalOne("NOT(0)"))
eq("TRUE literal", 1, evalOne("TRUE"))
eq("FALSE literal", 0, evalOne("FALSE"))
eq("nested calls", 10, evalOne("SUM(ABS(-4),POWER(2,1),4)"))
eq("function names are case-insensitive", 3, evalOne("sum(1,2)"))

-- ── Errors ─────────────────────────────────────────────────────────
do
  local d = evalOne("1/0")
  test("divide by zero errors", S.isErr(d))
  eq("with the DIV code", S.E_DIV, d.e)
  test("unknown function errors", S.isErr(evalOne("NOPE(1)")))
  eq("with the NAME code", S.E_NAME, evalOne("NOPE(1)").e)
  test("syntax error caught", S.isErr(evalOne("1+")))
  test("unbalanced parens caught", S.isErr(evalOne("(1+2")))
  test("unterminated string caught", S.isErr(evalOne('"abc')))
  test("trailing junk caught", S.isErr(evalOne("1 2")))
  test("garbage characters caught", S.isErr(evalOne("1 $ 2")))

  -- Errors PROPAGATE rather than being silently treated as zero.
  local sh = S.new()
  S.set(sh, 1, 1, "=1/0")
  S.set(sh, 1, 2, "=A1+1")
  S.set(sh, 1, 3, "=SUM(A1:A2)")
  local ctx = S.evaluator(sh)
  test("an error propagates through arithmetic", S.isErr(ctx.get(1, 2)))
  test("an error propagates through SUM", S.isErr(ctx.get(1, 3)))
  eq("the display shows the error code", S.E_DIV, S.display(sh, ctx, 1, 1))
end

-- ── Cycles ─────────────────────────────────────────────────────────
do
  local sh = S.new()
  S.set(sh, 1, 1, "=B1")
  S.set(sh, 2, 1, "=A1")
  local ctx = S.evaluator(sh)
  local v = ctx.get(1, 1)
  test("a 2-cell cycle is detected (not a hang)", S.isErr(v))
  eq("reported as #CYCLE!", S.E_CYCLE, v.e)

  local sh2 = S.new()
  S.set(sh2, 1, 1, "=A1")
  local ctx2 = S.evaluator(sh2)
  test("a self-reference is a cycle", S.isErr(ctx2.get(1, 1)))

  local sh3 = S.new()
  S.set(sh3, 1, 1, "=A2"); S.set(sh3, 1, 2, "=A3"); S.set(sh3, 1, 3, "=A1")
  local ctx3 = S.evaluator(sh3)
  test("a 3-cell cycle is detected", S.isErr(ctx3.get(1, 1)))
end

-- ── Deep-but-legal chains still evaluate ───────────────────────────
do
  local sh = S.new()
  S.set(sh, 1, 1, "1")
  for r = 2, 20 do S.set(sh, 1, r, "=A" .. (r - 1) .. "+1") end
  local ctx = S.evaluator(sh)
  eq("a 20-deep reference chain resolves", 20, ctx.get(1, 20))
end

-- ── SECURITY: a formula is DATA, never code ────────────────────────
-- The engine has no `load`, no `eval` and no way to reach a global. A
-- cell containing Lua source must evaluate to an error, NOT run.
do
  local ran = false
  _G.__calc_canary = function() ran = true end

  local attacks = {
    'os.exit()',
    'require("kernel.users")',
    '__calc_canary()',
    '(function() __calc_canary() end)()',
    'load("__calc_canary()")()',
    '1;__calc_canary()',
    '") __calc_canary() --',
  }
  local allErrored = true
  for _, a in ipairs(attacks) do
    local v = evalOne(a)
    -- Either a clean error, or (for something that happens to tokenize
    -- as a name) a #NAME? — never execution.
    if not S.isErr(v) then allErrored = false end
  end
  test("Lua source in a cell never evaluates cleanly", allErrored)
  test("...and NOTHING was executed", ran == false)
  _G.__calc_canary = nil

  -- The engine also refuses to reach real Lua functions by name.
  test("math.floor is not callable as a formula function",
    S.isErr(evalOne("math.floor(1.5)")))
  test("print is not callable", S.isErr(evalOne('print("x")')))
end

-- ── Serialization round-trip ───────────────────────────────────────
do
  local sh = S.new()
  S.set(sh, 1, 1, "10")
  S.set(sh, 2, 1, "=A1*2")
  S.set(sh, 1, 2, "hello world")
  S.set(sh, 27, 5, "far cell")           -- AA5
  local text = S.serialize(sh)
  test("serialize emits the header", text:sub(1, 8) == "TOSCALC1")
  test("cells appear by name", text:find("B1\t=A1*2", 1, true) ~= nil)

  local back = S.deserialize(text)
  eq("A1 round-trips", "10", S.raw(back, 1, 1))
  eq("the formula round-trips", "=A1*2", S.raw(back, 2, 1))
  eq("text round-trips", "hello world", S.raw(back, 1, 2))
  eq("a far cell round-trips", "far cell", S.raw(back, 27, 5))
  local ctx = S.evaluator(back)
  eq("the reloaded sheet still computes", 20, ctx.get(2, 1))

  -- Content that could forge a record is escaped.
  local sh2 = S.new()
  S.set(sh2, 1, 1, "has\ttab and\nnewline")
  local back2 = S.deserialize(S.serialize(sh2))
  eq("tabs/newlines survive escaping", "has\ttab and\nnewline", S.raw(back2, 1, 1))
  local forge = S.new()
  S.set(forge, 1, 1, "x\nZ9\tinjected")
  local back3 = S.deserialize(S.serialize(forge))
  eq("a cell cannot forge another cell", "", S.raw(back3, 26, 9))

  -- A corrupt file loads what it can instead of refusing outright.
  local partial = S.deserialize("TOSCALC1\nA1\tgood\n!!garbage!!\nB2\talso good\n")
  eq("good cells survive a corrupt file", "good", S.raw(partial, 1, 1))
  eq("...and later ones too", "also good", S.raw(partial, 2, 2))
  eq("the skipped count is reported", 1, partial.skipped)

  eq("deserializing junk yields an empty sheet", 0,
    (function() local s = S.deserialize("not a sheet at all"); local n = 0
      for _ in pairs(s.cells) do n = n + 1 end; return n end)())
end

-- ── CSV export ─────────────────────────────────────────────────────
do
  local sh = S.new()
  S.set(sh, 1, 1, "a"); S.set(sh, 2, 1, "1")
  S.set(sh, 1, 2, "b"); S.set(sh, 2, 2, "=B1+1")
  local ctx = S.evaluator(sh)
  local csv = S.toCSV(sh, ctx)
  test("CSV has a row per used row", select(2, csv:gsub("\n", "")) == 1)
  test("CSV exports VALUES, not formulas", csv:find("2") ~= nil
    and csv:find("=B1", 1, true) == nil)

  local sh2 = S.new()
  S.set(sh2, 1, 1, 'has,comma')
  S.set(sh2, 2, 1, 'has"quote')
  local csv2 = S.toCSV(sh2, S.evaluator(sh2))
  test("a comma-bearing value is quoted", csv2:find('"has,comma"', 1, true) ~= nil)
  test("an embedded quote is doubled", csv2:find('""quote', 1, true) ~= nil)
end

-- ── Display formatting ─────────────────────────────────────────────
eq("integers show plain", "42", dispOne("42"))
eq("a division showing thirds is trimmed", "0.3333", dispOne("1/3"))
eq("an error shows its code", S.E_DIV, dispOne("1/0"))
do
  local sh = S.new()
  S.set(sh, 1, 1, "text")
  eq("text displays as-is", "text", S.display(sh, S.evaluator(sh), 1, 1))
  eq("an empty cell displays blank", "", S.display(sh, S.evaluator(sh), 9, 9))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
