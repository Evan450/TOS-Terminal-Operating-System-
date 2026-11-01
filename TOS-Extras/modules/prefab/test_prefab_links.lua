-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: prefab with the rest of the pack                      ║
-- ║                                                              ║
-- ║  The other side of each link is the REAL package: stock's    ║
-- ║  own encode and decode, and the real printer driver and      ║
-- ║  formatter over a fake printer. A fake of them would agree   ║
-- ║  with whatever this expected, and every add-on with a thin   ║
-- ║  test has broken exactly at a seam like that. Each link is   ║
-- ║  also run with the other package missing.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/prefab/test_prefab_links.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "modules/?.lua;modules/printer/usr/lib/?.lua;" .. package.path

local HUT = [[
PREFAB1
name Starter hut
size 5 2 3
block a minecraft:cobblestone 0 Cobblestone
block g minecraft:glass 0 Glass
block r minecraft:wool 14 Red, "bright" wool
layer 1
aaaaa
aaaaa
aaaaa
layer 2
agrga
a...a
aaaaa
]]

local currentPrinter = nil
local component = {
  list = function(kind)
    local done = false
    return function()
      if done then return nil end
      done = true
      if kind == "openprinter" and currentPrinter then return "printer-1", kind end
    end
  end,
  proxy = function(addr)
    if addr == "printer-1" then return currentPrinter end
  end,
  isAvailable = function(kind) return kind == "openprinter" and currentPrinter ~= nil end,
  getPrimary = function(kind)
    if kind == "openprinter" and currentPrinter then return currentPrinter end
    error("no primary " .. kind)
  end,
}
package.loaded["component"] = component
package.loaded["computer"] = { uptime = function() return 0 end }

local fmt = require("printerfmt")
local function newPrinter()
  package.loaded["printer"] = nil
  return require("printer")
end
local Stock = require("stock.stock")
local B = require("prefab.blueprint")
local L = require("prefab.links")
local P = require("prefab.plan")

local function fakePrinter(opts)
  opts = opts or {}
  local p = { lines = {}, printed = {}, paper = opts.paper or 64, black = 100, color = 100 }
  function p.clear() p.lines = {}; return true end
  function p.setTitle(t) p.title = t; return true end
  function p.writeln(text, color, align)
    if #p.lines >= 20 then error("To many lines.") end
    p.lines[#p.lines + 1] = { text = text, color = color, align = align }
    return true
  end
  function p.print(copies)
    if p.paper < (copies or 1) then error("Please load Paper.") end
    p.paper = p.paper - (copies or 1)
    p.printed[#p.printed + 1] = { title = p.title, lines = p.lines }
    return true
  end
  function p.getPaperLevel() return p.paper end
  function p.getBlackInkLevel() return p.black end
  function p.getColorInkLevel() return p.color end
  function p.maxWidth() return 164 end
  function p.width(s) return fmt.width(s) end
  function p.charCount(s) return fmt.charCount(s) end
  return p
end

--- An inventory library over a list of stacks, in the shape the real one
--- returns: { key = "name#damage", count, label, ... } by side.
local function fakeInv(contents)
  local inv = {}
  function inv.available() return contents ~= false end
  function inv.sides()
    local out = {}
    for side in pairs(contents or {}) do out[#out + 1] = { side = side, name = "side" .. side, size = 27 } end
    table.sort(out, function(a, b) return a.side < b.side end)
    return out
  end
  function inv.stacks(side) return contents[side] end
  return inv
end
local function stack(id, damage, n)
  return { key = id .. "#" .. damage, id = id, damage = damage, count = n, label = id }
end

--- The real init.lua. opts says which other packages are installed.
local function machine(opts)
  opts = opts or {}
  local fx = { files = opts.files or {}, dirs = {}, out = {} }
  local fs = {
    exists = function(p) return fx.files[p] ~= nil or fx.dirs[p] == true end,
    readFile = function(p) return fx.files[p] end,
    makeDirectory = function(p) fx.dirs[p] = true; return true end,
    -- As a real machine does it: a refusal is a return, not an error, and
    -- /etc is closed but for its exempt list, of which this is the one entry
    -- that matters here. build/test_addon_cfg_writable.py checks the real list.
    writeFile = function(p, d)
      if p:sub(1, 5) == "/etc/" and p ~= Stock.WATCH_FILE then
        return false, "Refused: writing to /etc is a protected system path."
      end
      if opts.deny and p:sub(1, #opts.deny) == opts.deny then return false, "access denied" end
      fx.files[p] = d
      return true
    end,
  }
  local env
  local function req(name)
    if name == "component" then return component end
    if name == "computer" then return package.loaded["computer"] end
    if name:sub(1, 7) == "prefab." then return require(name) end
    if name == "peripheral.inventory" then
      if opts.inv ~= nil then return fakeInv(opts.inv) end
      error("no inventory", 2)
    end
    if name == "stock.stock" and opts.stock then return Stock end
    if name == "printerfmt" and opts.printer then return fmt end
    if name == "printer" and opts.printer then
      fx.driver = fx.driver or newPrinter()
      return fx.driver
    end
    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
  env = setmetatable({ require = req, fs = fs }, { __index = _G })
  local main = assert(loadfile("modules/prefab/init.lua", "t", env))()
  fx.run = function(args)
    fx.out = {}
    main.commands.prefab(args, function(t) fx.out[#fx.out + 1] = tostring(t) end)
    return table.concat(fx.out, "\n")
  end
  return fx
end

local function has(s, n) return s ~= nil and s:find(n, 1, true) ~= nil end

print("=== have against need ===")
print()

do
  local bp = B.parse(HUT)
  local rows, short = L.need(bp, {
    stack("minecraft:cobblestone", 0, 18), stack("minecraft:cobblestone", 0, 5),
    stack("minecraft:glass", 0, 9), stack("minecraft:wool", 3, 64), stack("minecraft:dirt", 0, 64) })
  test("the worst shortage comes first", rows[1].id == "minecraft:cobblestone" and rows[1].short == 1, rows[1].short)
  test("stacks on different sides add up", rows[1].have == 23)
  test("wool of another colour is not this wool", rows[2].key == "minecraft:wool#14" and rows[2].have == 0, rows[2].key)
  test("more than enough is not negative", rows[3].short == 0 and rows[3].have == 9)
  test("the total is what is missing", short == 2, short)
end

do
  local file = { ["/hut.bp"] = HUT }
  local inv = { [2] = { stack("minecraft:cobblestone", 0, 24) }, [3] = { stack("minecraft:glass", 0, 2), stack("minecraft:wool", 14, 1) } }
  local out = machine({ files = file, inv = inv }).run({ "need", "/hut.bp" })
  test("need names what it read", has(out, "side2, side3"), out)
  test("...and says when you have it all", has(out, "You have everything it takes."), out)
  inv[2][1].count = 18
  local fx = machine({ files = file, inv = inv })
  local short = fx.run({ "need", "/hut.bp" })
  test("...and what is short", has(short, "(6 short)") and has(short, "6 block(s) short."), short)
  test("without stock it does not mention stock", not has(short, "stock"), short)
  local withStock = machine({ files = file, inv = inv, stock = true }).run({ "need", "/hut.bp" })
  test("with stock it offers the watch", has(withStock, "prefab watch"), withStock)
  test("no transposer says so", has(machine({ files = file, inv = false }).run({ "need", "/hut.bp" }), "no inventory controller or transposer"))
  test("no inventory library says so", has(machine({ files = file }).run({ "need", "/hut.bp" }), "not available"))
  test("no blueprint named says so", has(machine({ files = file, inv = inv }).run({ "need" }), "Which blueprint?"))
end

print()
print("=== stock ===")
print()

do
  local bp = B.parse(HUT)
  local watches, labels = {}, {}
  local n = L.watch(watches, labels, bp)
  test("a build becomes watches", n == 3, n)
  watches, labels = Stock.decodeWatches(Stock.encodeWatches(watches, labels))
  test("they survive stock's own encoder", watches["minecraft:cobblestone#0"] == 24, watches["minecraft:cobblestone#0"])
  test("the label comes across for stock's screen", labels["minecraft:glass#0"] == "Glass")
  local rows = Stock.applyWatches({}, watches, labels)
  test("stock's monitor shows a watched block you have none of", #rows == 3 and rows[1].low == true and rows[1].absent == true)
  test("stock's low list has them", #Stock.lowStock(rows) == 3)

  local merged, mergedLabels = { ["minecraft:glass#0"] = 500, ["minecraft:iron_ingot#0"] = 16 }, {}
  L.watch(merged, mergedLabels, bp)
  test("a higher threshold someone set stays", merged["minecraft:glass#0"] == 500)
  test("what the build has nothing to do with stays", merged["minecraft:iron_ingot#0"] == 16)

  local gone = L.unwatch(merged, mergedLabels, bp)
  test("--off takes the build's own thresholds away", gone == 2 and merged["minecraft:cobblestone#0"] == nil, gone)
  test("...and leaves anyone else's", merged["minecraft:glass#0"] == 500 and merged["minecraft:iron_ingot#0"] == 16)

  local fx = machine({ files = { ["/hut.bp"] = HUT }, stock = true })
  local said = fx.run({ "watch", "/hut.bp" })
  test("watch writes stock's own file", fx.files[Stock.WATCH_FILE] ~= nil and has(said, "stock is watching 3 block(s)"), said)
  test("...which stock's decoder accepts", Stock.decodeWatches(fx.files[Stock.WATCH_FILE])["minecraft:wool#14"] == 1)
  test("--off says what it did", has(fx.run({ "watch", "/hut.bp", "--off" }), "stopped watching 3"))
  test("without stock it says what to install",
    has(machine({ files = { ["/hut.bp"] = HUT } }).run({ "watch", "/hut.bp" }), "pkg install stock"))
  local denied = machine({ files = { ["/hut.bp"] = HUT }, stock = true, deny = Stock.WATCH_FILE }).run({ "watch", "/hut.bp" })
  test("a user who cannot write it is told why", has(denied, "Not saved: access denied") and has(denied, "admin"), denied)
end

do
  -- A tab in a label must not break stock's tab-separated file.
  local bp = B.new(1, 1, 1, "T")
  bp.palette.a = { id = "m:a", meta = 0, label = "two\tcolumns" }
  bp.order = { "a" }
  B.set(bp, 1, 1, 1, "a")
  local w, labels = {}, {}
  L.watch(w, labels, bp)
  local out = Stock.encodeWatches(w, labels)
  local w2, labels2 = Stock.decodeWatches(out)
  test("a label cannot add a column to stock's file", w2["m:a#0"] == 1 and labels2["m:a#0"] == "two columns", out)
end

print()
print("=== printer ===")
print()

do
  local bp = B.parse(HUT)
  currentPrinter = fakePrinter()
  local printer = newPrinter()
  local job = L.printJob(printer.job(bp.name), bp, P.report(bp, 16), printer.maxWidth())
  test("a sheet of materials and a page a layer", #job:pages() == 3, #job:pages())
  local done, err = job:commit()
  test("the real driver prints it", done == 3, err)
  local first = currentPrinter.printed[1].lines
  test("it opens with the name", first[1].text == "Starter hut" and first[1].align == "center", first[1].text)
  local text = {}
  for _, l in ipairs(first) do text[#text + 1] = l.text end
  test("...and the materials, by letter", has(table.concat(text, "\n"), "A  24  Cobblestone"), table.concat(text, "\n"))
  local layer2 = currentPrinter.printed[3].lines
  test("a layer prints as a grid", layer2[1].text == "Layer 2 of 2" and layer2[2].text == "ABCBA", layer2[2].text)
  test("air prints as a dash, which is as wide as a letter", layer2[3].text == "A---A", layer2[3].text)
  test("every printed row of a plan is one width",
    fmt.width(layer2[2].text) == fmt.width(layer2[3].text),
    fmt.width(layer2[2].text) .. " vs " .. fmt.width(layer2[3].text))
  test("a printed title is the blueprint's", currentPrinter.printed[1].title == "Starter hut")
end

do
  -- Wider than the paper: strips, and every cell lands on one.
  local bp = B.new(40, 1, 2, "Wall")
  B.addBlock(bp, "a", "minecraft:stone", 0, "Stone")
  for x = 1, 40 do B.set(bp, x, 1, 1, "a") end
  currentPrinter = fakePrinter()
  local job = L.printJob(newPrinter().job("Wall"), bp, P.report(bp, 16), 164)
  test("a row wider than the paper goes in strips", #job:pages() == 3, #job:pages())
  local cells = 0
  for i = 2, #job:pages() do
    local page = job:pages()[i]
    test("strip " .. (i - 1) .. " is headed with its range", has(page[1].text, "X "), page[1].text)
    for _, c in page[2].text:gmatch("()A") do cells = cells + 1; local _ = c end
    test("strip " .. (i - 1) .. " fits the paper", fmt.width(page[2].text) <= 164, fmt.width(page[2].text))
  end
  test("no cell is lost between strips", cells == 40, cells)
end

do
  local file = { ["/hut.bp"] = HUT }
  currentPrinter = fakePrinter()
  local fx = machine({ files = file, printer = true })
  local out = fx.run({ "print", "/hut.bp" })
  test("print prints, and says how much", has(out, "3 page(s)") and has(out, "Printed 3 page(s)."), out)
  test("...on real paper", #currentPrinter.printed == 3)
  currentPrinter = fakePrinter()
  local dry = machine({ files = file, printer = true }).run({ "print", "/hut.bp", "--dry" })
  test("--dry prints nothing", has(dry, "3 page(s)") and #currentPrinter.printed == 0, dry)
  currentPrinter = nil
  local none = machine({ files = file, printer = true }).run({ "print", "/hut.bp" })
  test("no printer attached says so", has(none, "No printer"), none)
  test("--dry works with no printer at all", has(machine({ files = file, printer = true }).run({ "print", "/hut.bp", "--dry" }), "3 page(s)"))
  test("without the package it says what to install",
    has(machine({ files = file }).run({ "print", "/hut.bp" }), "pkg install printer"))
  currentPrinter = fakePrinter({ paper = 1 })
  local short = machine({ files = file, printer = true }).run({ "print", "/hut.bp" })
  test("short of paper it stops before wasting any", has(short, "Stopped after 0 page(s)") and has(short, "needs 3 sheets"), short)
  currentPrinter = nil
end

print()
print("=== calc ===")
print()

do
  local bp = B.parse(HUT)
  local csv = L.csv(bp)
  test("the bill of materials has a header", has(csv, "Block,Registry name,Damage,Count,Stacks\n"), csv)
  test("...and a row a block", has(csv, "Cobblestone,minecraft:cobblestone,0,24,1\n"), csv)
  test("a comma or a quote in a label is quoted", has(csv, '"Red, ""bright"" wool",minecraft:wool,14,1,1'), csv)
  package.path = "modules/?.lua;" .. package.path
  local S = require("calc.sheet")
  local sh = S.new and S.new() or nil
  if sh then
    local ok, err = pcall(S.fromCSV, sh, csv, 1, 1)
    test("calc's own importer reads it", ok, err)
    test("...with the quoted label in one cell", has(S.raw(sh, 1, 4), 'Red, "bright" wool'), S.raw(sh, 1, 4))
    test("...and the count in its own", has(S.raw(sh, 4, 4), "1"), S.raw(sh, 4, 4))
  end

  local rows = L.need(bp, { stack("minecraft:cobblestone", 0, 10) })
  local withHave = L.csv(bp, rows)
  test("with inventories in reach it adds what you have", has(withHave, "Stacks,Have,Short\n")
    and has(withHave, "Cobblestone,minecraft:cobblestone,0,24,1,10,14\n"), withHave)

  local fx = machine({ files = { ["/hut.bp"] = HUT } })
  local said = fx.run({ "csv", "/hut.bp", "/m.csv" })
  test("csv writes the file", fx.files["/m.csv"] ~= nil and has(said, "Wrote /m.csv."), said)
  test("...and works with nothing else installed", not has(said, "calc"), said)
  local withCalc = machine({ files = { ["/hut.bp"] = HUT, ["/usr/modules/calc/init.lua"] = "x" } })
  test("with calc installed it says how to open it", has(withCalc.run({ "csv", "/hut.bp", "/m.csv" }), "calc /m.csv opens it"))
  local inReach = machine({ files = { ["/hut.bp"] = HUT }, inv = { [2] = { stack("minecraft:glass", 0, 1) } } })
  test("with inventories in reach it says so", has(inReach.run({ "csv", "/hut.bp", "/m.csv" }), "with what you have"))
  test("it says what it needs", has(fx.run({ "csv", "/hut.bp" }), "prefab csv"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
