-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: calc's 1-2-3 screen, driven like an operator would    ║
-- ║                                                              ║
-- ║  Loads the REAL init.lua inside a fake of the package        ║
-- ║  sandbox (a GPU that keeps a screen buffer, a keyboard fed   ║
-- ║  from a script, a session fs) and types at it: entries,      ║
-- ║  pointing at cells mid-formula, the / menu by first letters, ║
-- ║  saving, printing to a file, to the printer and into write.  ║
-- ║  The engine has its own tests; this is the seam between the  ║
-- ║  keys and the engine, where a menu that runs the wrong       ║
-- ║  command or a prompt that eats a key would otherwise only    ║
-- ║  show up at a real keyboard.                                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/calc/test_calc_ui.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local ROOT = "modules/calc/"

local function utf8chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

-- Keys as OpenComputers sends them: (key_down, kbd, char, code).
local function key(code, ch) return { "key_down", "kbd", ch or 0, code } end
local function char(c) return key(0, c:byte()) end
local function typed(s) local t = {} for c in s:gmatch(".") do t[#t + 1] = char(c) end return t end
local ENTER, UP, DOWN, LEFT, RIGHT = key(28, 13), key(200), key(208), key(203), key(205)
local BKSP, CTRL_Q, F2 = key(14, 8), key(16, 17), key(60)
local function script(...)
  local out = {}
  for _, part in ipairs({ ... }) do
    if part[1] == "key_down" then out[#out + 1] = part
    else for _, k in ipairs(part) do out[#out + 1] = k end end
  end
  return out
end

local function run(opts)
  opts = opts or {}
  local W, H = opts.W or 80, opts.H or 25
  local fx = { files = opts.files or {}, screens = {}, printed = nil, composed = nil }
  local rows = {}
  for y = 1, H do rows[y] = {} for x = 1, W do rows[y][x] = " " end end
  local function text() local t = {} for y = 1, H do t[y] = table.concat(rows[y]) end return table.concat(t, "\n") end
  local gpu = {
    getResolution = function() return W, H end,
    getDepth = function() return 8 end,
    setForeground = function() end, setBackground = function() end,
    set = function(x, y, s)
      if y < 1 or y > H then return end
      for i, ch in ipairs(utf8chars(s)) do local xx = x + i - 1; if xx >= 1 and xx <= W then rows[y][xx] = ch end end
    end,
    fill = function(x, y, w, h, ch)
      for yy = y, y + h - 1 do for xx = x, x + w - 1 do
        if yy >= 1 and yy <= H and xx >= 1 and xx <= W then rows[yy][xx] = ch end
      end end
    end,
  }
  local component = {
    list = function(t) local done = false
      return function() if done or t ~= "gpu" then return nil end done = true return "gpu", "gpu" end end,
    proxy = function() return gpu end,
  }
  local queue = {}
  for _, k in ipairs(opts.keys or {}) do queue[#queue + 1] = k end
  local spare = 0
  local computer = {
    pullSignal = function()
      fx.screens[#fx.screens + 1] = text()
      local s = table.remove(queue, 1)
      if s then return table.unpack(s) end
      -- Out of script: interrupt (read as ^Q) a few times, then stop the
      -- run outright. With unsaved changes calc keeps asking "leave
      -- anyway?", rightly, and a script that forgot to answer would spin.
      spare = spare + 1
      if spare > 8 then error("the key script ran out", 0) end
      return "interrupted"
    end,
    beep = function() fx.beeps = (fx.beeps or 0) + 1 end,
    freeMemory = function() return 512 * 1024 end,
  }
  local fs = {
    home = function() return "/home/tester" end,
    exists = function(p) return fx.files[p] ~= nil end,
    isDirectory = function(p) return p == "/home/tester" end,
    list = function(d)
      local out = {}
      for p in pairs(fx.files) do
        local dd, n = p:match("^(.*)/([^/]+)$")
        if dd == d then out[#out + 1] = n end
      end
      return out
    end,
    readFile = function(p) return fx.files[p] end,
    writeFile = function(p, d) fx.files[p] = d; return true end,
  }
  local env
  local loaded = {}
  local function req(name)
    if name == "component" then return component end
    if name == "computer" then return computer end
    if name:sub(1, 5) == "calc." then
      if loaded[name] then return loaded[name] end
      loaded[name] = assert(loadfile(ROOT .. name:sub(6) .. ".lua", "t", env))()
      return loaded[name]
    end
    if name == "printerfmt" then
      loaded[name] = loaded[name] or assert(loadfile("modules/printer/usr/lib/printerfmt.lua", "t", env))()
      return loaded[name]
    end
    if name == "printer" and opts.printer then
      local fmt = req("printerfmt")
      return {
        available = function() return true end,
        unavailableReason = function() return nil end,
        measurer = function() return fmt.width end,
        maxWidth = function() return fmt.MAX_WIDTH end,
        width = function(s) return fmt.width(s), "component" end,
        job = function(title)
          local job = { pages = { {} }, title = title }
          function job:line(t) local pg = self.pages[#self.pages]; pg[#pg + 1] = t; return self end
          function job:pageBreak() self.pages[#self.pages + 1] = {}; return self end
          function job:check() return true end
          function job:commit() fx.printed = self; return #self.pages end
          return job
        end,
      }
    end
    if name == "write" and opts.write then
      return { api = { VERSION = "1.1.0", open = function(path, t) fx.composed = { path = path, text = t }; return true end } }
    end
    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
  env = setmetatable({ require = req, fs = fs }, { __index = _G })
  local main = assert(loadfile(ROOT .. "init.lua", "t", env))()
  fx.ok, fx.err = pcall(main.commands.calc, opts.args or {}, function(t) fx.said = t end)
  function fx.any(pat)
    for _, s in ipairs(fx.screens) do if s:find(pat, 1, true) then return true end end
    return false
  end
  function fx.sheet()
    local S = req("calc.sheet")
    return S, S.deserialize(fx.files["/home/tester/sheet.calc"] or "")
  end
  return fx
end

print("=== Entering, the 1-2-3 way ===")
do
  local fx = run({ keys = script(
    typed("Sales"), { DOWN },            -- a label; the arrow enters it and moves
    typed("10"), { DOWN }, typed("20"), { DOWN }, typed("30"), { DOWN },
    typed("@SUM("), { UP, UP, UP }, typed("."), { DOWN, DOWN }, typed(")"), { ENTER },
    typed("/fs"), { ENTER },               -- /File Save, the default name
    { CTRL_Q }) })
  test("ran to the end without an error" .. (fx.ok and "" or (": " .. tostring(fx.err))), fx.ok)
  test("READY shows in the corner", fx.any(" READY "))
  test("a letter starts LABEL mode", fx.any(" LABEL "))
  test("a digit starts VALUE mode", fx.any(" VALUE "))
  test("an arrow after ( starts POINT mode", fx.any(" POINT "))
  test("pointing shows the address being built", fx.any("@SUM(A2..A4"))
  test("the control panel shows the cell and its contents", fx.any("A5: @SUM(A2..A4)"))
  local S, sh = fx.sheet()
  test("the file was saved under the default name", fx.files["/home/tester/sheet.calc"] ~= nil)
  test("a label got the default ' prefix", S.raw(sh, 1, 1) == "'Sales")
  test("pointing built @SUM(A2..A4)", S.raw(sh, 1, 5) == "@SUM(A2..A4)")
  test("and it computes 60", S.evaluator(sh).get(1, 5) == 60)
  test("the total shows on the grid", fx.any("       60"))
end

do
  -- A value that does not parse drops into EDIT with the error, as 1-2-3
  -- did; ' at the front makes it a label.
  local fx = run({ keys = script(typed("5 apples"), { ENTER },
    { key(199) }, typed("'"), { ENTER }, typed("/fs"), { ENTER }, { CTRL_Q }) })
  test("a broken value says why", fx.any("Not a valid formula"))
  test("and is left in EDIT mode", fx.any(" EDIT "))
  local S, sh = fx.sheet()
  test("Home, ' and Enter made it a label", S.raw(sh, 1, 1) == "'5 apples")
end

print()
print("=== The / menu ===")
do
  local fx = run({ keys = script(
    typed("234.5"), { ENTER },
    typed("/rfc"), { ENTER }, { ENTER },  -- /Range Format Currency, 2 places, A1..A1
    { DOWN }, typed("1234.5"), { ENTER },
    typed("/rfc"), { ENTER }, { ENTER },  -- the same in a 9-wide column: too wide
    typed("/fs"), { ENTER }, { CTRL_Q }) })
  test("the menu shows its items", fx.any("Worksheet  Range  Copy  Move  File  Print  Graph  Data  Quit"))
  test("the third line previews the next level", fx.any("Format  Label  Erase  Name  Value"))
  test("the highlighted leaf's description shows", fx.any("Fixed number of decimal places: x.xx"))
  test("the decimals prompt", fx.any("Enter number of decimal places (0..15): 2"))
  test("the range prompt starts anchored at the pointer", fx.any("Enter range to format: A1..A1"))
  test("Currency shows on the grid", fx.any(" $234.50 "))
  test("too wide for the column shows asterisks, never a wrong number", fx.any("********"))
end

do
  local fx = run({ keys = script(
    typed("1"), { DOWN }, typed("2"), { DOWN }, typed("3"), { DOWN },
    typed("+A1*10"), { ENTER },                         -- A4
    typed("/c"), { ENTER }, { RIGHT }, { ENTER },        -- /Copy A4 to B4
    { UP, UP }, typed("/wir"), { ENTER },               -- /Worksheet Insert Row at A2
    typed("/fs"), { ENTER }, { CTRL_Q }) })
  local S, sh = fx.sheet()
  test("/Copy shifted the relative reference", S.raw(sh, 2, 5) == "+B1*10")
  test("/Worksheet Insert Row moved the rows and the formulas", S.raw(sh, 1, 5) == "+A1*10" and S.raw(sh, 1, 3) == "2")
end

do
  -- /Print File: range, go, a .prn on disk; the Print menu waits for Quit.
  local fx = run({ keys = script(
    typed("Item"), { RIGHT }, typed("Qty"), { DOWN }, { LEFT },
    typed("Bolts"), { RIGHT }, typed("12"), { ENTER },
    typed("/pfr"), { BKSP }, typed("A1..B2"), { ENTER },
    typed("g"), { ENTER }, typed("q"),
    typed("/fs"), { ENTER }, { CTRL_Q }) })
  test("the print menu has no Printer without the driver", not fx.any("Printer  File"))
  test("and no Document without write", not fx.any("Document"))
  local prn = fx.files["/home/tester/sheet.prn"]
  test("a .prn was written", prn ~= nil)
  test("with the label and the number lined up", prn and prn:find("Bolts", 1, true) and prn:find("12", 1, true))
  local _, sh = fx.sheet()
  test("the print range is kept with the worksheet", sh.print.range == "A1..B2")
end

do
  -- With the printer driver and write installed, the Print menu offers both.
  local fx = run({ printer = true, write = true,
    files = { ["/usr/lib/printer.lua"] = "--", ["/usr/modules/write/init.lua"] = "--" },
    keys = script(
      typed("Total"), { RIGHT }, typed("99"), { ENTER },
      typed("/ppr"), { BKSP }, typed("A1..B1"), { ENTER },
      typed("g"), typed("y"), typed("q"),          -- Go, Yes print, Quit
      typed("/pdr"), { BKSP }, typed("A1..B1"), { ENTER }, typed("g"), typed("q"),
      { CTRL_Q }, typed("y")) })
  test("the Print menu offers Printer, File and Document", fx.any("Printer  File  Document"))
  test("printing asks first, with the cost", fx.any("Print 1 sheet(s), 0 black ink?  No  Yes")
    or fx.any("Print 1 sheet(s), 1 black ink?  No  Yes"))
  test("the printer got the range", fx.printed and fx.printed.pages[1][1]:find("Total", 1, true) ~= nil)
  test("write was handed the document", fx.composed ~= nil)
  test("as no-fill text, so its columns survive", fx.composed and fx.composed.text:sub(1, 4) == ".nf\n")
  test("titled, with a path to save it at", fx.composed and fx.composed.text:find(".title", 1, true) and fx.composed.path:match("%.txt$"))
end

do
  -- /Graph: A range, View; then /Data Sort descending.
  local fx = run({ keys = script(
    typed("3"), { DOWN }, typed("9"), { DOWN }, typed("5"), { UP, UP },
    typed("/ga"), { DOWN, DOWN }, { ENTER }, typed("v"), char(" "), typed("q"),
    typed("/dsd"), { DOWN, DOWN }, { ENTER }, typed("p"), { ENTER }, { BKSP }, typed("D"), { ENTER }, typed("g"),
    typed("/fs"), { ENTER }, { CTRL_Q }) })
  test("the graph draws its bars", fx.any("\226\150\136"))
  test("with its legend", fx.any("  A"))
  local S, sh = fx.sheet()
  test("/Data Sort descending", S.raw(sh, 1, 1) == "9" and S.raw(sh, 1, 3) == "3")
  test("the graph settings are kept", sh.graph.a == "A1..A3")
end

do
  -- `calc data.csv` (what `open` hands over) imports, and saves as .calc
  -- beside it: the CSV itself is never rewritten as a worksheet.
  local csv = "Item,Qty\nBolts,12\n"
  local fx = run({ args = { "/home/tester/data.csv" }, files = { ["/home/tester/data.csv"] = csv },
    keys = script({ key(0, 19) }, { CTRL_Q }) })     -- ^S, then quit
  test("a CSV on the command line is imported", fx.any("Imported 4 cell(s) from /home/tester/data.csv"))
  test("^S saves it as data.calc", fx.files["/home/tester/data.calc"] ~= nil
    and fx.files["/home/tester/data.calc"]:find("Bolts", 1, true) ~= nil)
  test("and the CSV is untouched", fx.files["/home/tester/data.csv"] == csv)
end

do
  -- Quitting with unsaved changes asks.
  local fx = run({ keys = script(typed("1"), { ENTER }, { CTRL_Q }, typed("n"), { CTRL_Q }, typed("y")) })
  test("unsaved changes: Quit asks No / Yes / Save", fx.any("Leave anyway?  No  Yes  Save"))
  test("No stays, Yes leaves", fx.ok and #fx.screens > 3)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All tests passed.")
