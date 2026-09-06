-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Integration Test: console -> controller -> wire -> panel     ║
-- ║                                                              ║
-- ║  test_rbmk.lua proves the safety rules and test_rbmk_skala   ║
-- ║  proves the panel's arithmetic. Neither proves the pieces     ║
-- ║  are CONNECTED, and that is its own failure mode: every      ║
-- ║  half can be right while the seam between them is wrong.     ║
-- ║                                                              ║
-- ║  So this drives the whole chain against fakes: a console     ║
-- ║  component with real-looking methods, a modem that captures  ║
-- ║  what was broadcast, and a display that REMEMBERS EVERY      ║
-- ║  CELL it was told to paint.                                  ║
-- ║                                                              ║
-- ║  That last part is the point. A mock that counts calls tests ║
-- ║  that we CALLED something; only a mock that models state     ║
-- ║  tests that we called it CORRECTLY. So the assertions here   ║
-- ║  read the finished screen — "the cell for channel 7,4 says   ║
-- ║  361 and is drawn in the alarm colour" — rather than "set()  ║
-- ║  was called 225 times".                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua rbmk/test_rbmk_panel.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond, oops)
  if oops ~= nil then
    error("test(name, cond) takes 2 arguments; got 3. Did you mean eq()?", 2)
  end
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ", want " .. tostring(expected) .. ")",
    expected == actual)
end

local base = ((arg and arg[0]) or "rbmk/test_rbmk_panel.lua"):gsub("[^/\\]*$", "")
local LIB = base .. "controller-skeleton/usr/lib/"
package.path = "rbmk/controller-skeleton/usr/lib/?.lua;"
  .. "rbmk/controller-skeleton/usr/lib/?/init.lua;"
  .. LIB .. "?.lua;" .. LIB .. "?/init.lua;" .. package.path

print("=== RBMK end-to-end: console -> wire -> panel ===")
print()

-- ══════════════════════════════════════════════════════════════════
-- Fakes
-- ══════════════════════════════════════════════════════════════════

-- A reactor whose numbers we control. The method NAMES are the
-- profile's first candidates, which is also a check that the shipped
-- candidate list is what the code actually looks for.
local reactor = {
  temp = 500, flux = 3000, water = 90, steam = 40, rodDepth = 50,
  scrammed = false, cols = {},
}
for y = 1, 15 do
  for x = 1, 15 do
    reactor.cols[#reactor.cols + 1] = {
      x = x, y = y, kind = (x % 3 == 0) and "control" or "fuel",
      temp = 300 + x * 7 + y * 3, flux = 1000 + x * 100,
      steam = 40, rodDepth = 50, water = 90,
    }
  end
end

local console = {
  getTemp     = function() return reactor.temp end,
  getFlux     = function() return reactor.flux end,
  getWater    = function() return reactor.water end,
  getSteam    = function() return reactor.steam end,
  getRodDepth = function() return reactor.rodDepth end,
  getColumnData = function() return reactor.cols end,
  setAZ5      = function() reactor.scrammed = true; return true end,
}

local sent = {}          -- every modem.broadcast, in order
local modem = {
  broadcast = function(port, ...)
    sent[#sent + 1] = { port = port, args = table.pack(...) }
    return true
  end,
  open = function() return true end,
  close = function() return true end,
}

local COMPONENTS = {
  ["c0nsole-0000-0000-0000-000000000001"] = { type = "rbmk_console", proxy = console },
  ["m0dem-0000-0000-0000-0000000000002"]  = { type = "modem",        proxy = modem },
}

package.loaded["component"] = {
  list = function(filter)
    local keys = {}
    for a, c in pairs(COMPONENTS) do
      if not filter or c.type == filter then keys[#keys + 1] = a end
    end
    table.sort(keys)
    local i = 0
    return function()
      i = i + 1
      if keys[i] then return keys[i], COMPONENTS[keys[i]].type end
    end
  end,
  proxy = function(addr)
    return COMPONENTS[addr] and COMPONENTS[addr].proxy or nil
  end,
  methods = function(addr)
    local names = {}
    local p = COMPONENTS[addr] and COMPONENTS[addr].proxy
    for k, v in pairs(p or {}) do
      if type(v) == "function" then names[#names + 1] = k end
    end
    return names
  end,
}

local clock = 100
package.loaded["computer"] = {
  uptime = function() return clock end,
  beep = function() return true end,
  pullSignal = function() return nil end,
}

local ticker
package.loaded["kernel.event"] = {
  interval = function(_, cb) ticker = cb; return 1 end,
  cancelTimer = function() return true end,
  on = function() return 1 end,
  off = function() return true end,
}

local logged = {}
package.loaded["kernel.log"] = {
  info  = function(_, m) logged[#logged + 1] = { "info", m } end,
  warn  = function(_, m) logged[#logged + 1] = { "warn", m } end,
  error = function(_, m) logged[#logged + 1] = { "error", m } end,
  debug = function() end,
}

-- The config, served from memory so no real file is touched.
local CFG_SRC = [[
return {
  name = "rbmk-test", pollInterval = 1, mapInterval = 1,
  telemetryPort = 2200,
  grid = { w = 15, h = 15, shape = "square" },
  limits = { tempWarn = 800, tempScram = 1000, waterMin = 10 },
}
]]
package.loaded["kernel.fs"] = {
  exists = function(p) return p == "/etc/rbmk.cfg" end,
  readFile = function(p) return p == "/etc/rbmk.cfg" and CFG_SRC or nil end,
}

local core  = require("rbmk.core")
local skala = require("rbmk.skala")
local cmd   = require("rbmk-cmd")
local ui    = require("rbmk-skala")
local controld = require("rbmk-controld")

-- ══════════════════════════════════════════════════════════════════
print("-- the controller binds a real-looking console --")
-- ══════════════════════════════════════════════════════════════════
do
  local cfg = cmd.loadCfg()
  eq("the config is read", "rbmk-test", cfg.name)
  local binding = core.bind(cmd.activeProfile(cfg),
    cmd.methodsOf("c0nsole-0000-0000-0000-000000000001"))
  eq("temperature binds to a shipped candidate", "getTemp", binding.bound.temp)
  eq("SCRAM binds", "setAZ5", binding.bound.scram)
  eq("the core map's accessor binds", "getColumnData", binding.columns)
  --! This console has no getFuel, and `fuel` is exactly what should be
  --! reported missing -- not silently bound to something else, and not
  --! swept into the count of things that worked.
  eq("the one reading this console lacks is reported", 1, #binding.missing)
  eq("...and it is named", "fuel", binding.missing[1])
  test("the binding is usable", (core.bindingUsable(binding, false)))

  local ok = controld.start()
  eq("the service starts against this console", true, ok)
  test("...and an interval was armed", ticker ~= nil)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- one poll produces one broadcast --")
-- ══════════════════════════════════════════════════════════════════
local frame
do
  clock = clock + 1
  ticker()
  eq("exactly one frame went out", 1, #sent)
  eq("...on the telemetry port", core.TELEMETRY_PORT, sent[1].port)
  eq("...with the fixed argument count", core.WIRE_ARGS, sent[1].args.n)

  --! The defect this release fixes: telemetry used to go out as a TOS
  --! protocol MSG, which net/trust.lua allows only at TRUSTED -- so no
  --! untrusted display could receive it, and OpenOS could not parse it
  --! at all. A raw modem broadcast is what a display can actually hear.
  eq("the frame is raw modem arguments, not a serialized packet",
    "RBMK", sent[1].args[1])
  local tabled = 0
  for i = 1, sent[1].args.n do
    if type(sent[1].args[i]) == "table" then tabled = tabled + 1 end
  end
  eq("...and carries no table for a display to deserialize", 0, tabled)

  frame = core.decodeWire(table.unpack(sent[1].args, 1, sent[1].args.n))
  test("a display can decode what the controller sent", frame ~= nil)
  eq("the reactor's name arrives", "rbmk-test", frame and frame.name)
  eq("the temperature arrives", 500, frame and frame.temp)
  eq("the level arrives", "ok", frame and frame.level)
  test("the core map arrives", frame and type(frame.cols) == "string")
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the map survives the round trip with real values --")
-- ══════════════════════════════════════════════════════════════════
local cols, grid
do
  cols, grid = core.unpackColumns(frame.cols, skala.PARAMS)
  eq("every channel arrives", 225, cols and #cols)
  eq("the grid arrives", 15, grid and grid.w)
  local ix = core.columnIndex(cols)
  eq("channel 7,4 keeps its temperature", 300 + 49 + 12, ix["7,4"].temp)
  eq("channel 6,2 keeps its kind", "control", ix["6,2"].kind)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the panel paints it --")
-- ══════════════════════════════════════════════════════════════════
--! A display that records what each cell HOLDS. Nothing here counts
--! calls: every assertion below reads the finished screen.
local function fakeDisplay(W, H)
  local ch, fg = {}, {}
  local d = {}
  function d.getSize() return W, H end
  function d.getTheme()
    return { bg = 0x000000, fg = 0xFFFFFF, dim = 0xAAAAAA, title = 0x00AAFF,
             error = 0xFF0000, warning = 0xFFAA00, highlight = 0x00FF00 }
  end
  function d.clear() ch, fg = {}, {} end
  function d.set(x, y, s, f)
    if type(s) ~= "string" then return end
    local i = 1
    -- Walk UTF-8 so a block character occupies one cell, as it does on
    -- a real GPU.
    for c in s:gmatch("[\1-\127\194-\244][\128-\191]*") do
      ch[(y * 1000) + x + i - 1] = c
      fg[(y * 1000) + x + i - 1] = f
      i = i + 1
    end
  end
  function d.fill(x, y, w, h, c, f)
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do
        ch[(yy * 1000) + xx] = c; fg[(yy * 1000) + xx] = f
      end
    end
  end
  function d.textAt(x, y, n)
    local out = {}
    for i = 0, n - 1 do out[#out + 1] = ch[(y * 1000) + x + i] or " " end
    return table.concat(out)
  end
  function d.colorAt(x, y) return fg[(y * 1000) + x] end
  function d.rowText(y)
    local out = {}
    for x = 1, W do out[#out + 1] = ch[(y * 1000) + x] or " " end
    return (table.concat(out):gsub("%s+$", ""))
  end
  function d.screenText()
    local out = {}
    for y = 1, H do out[#out + 1] = d.rowText(y) end
    return table.concat(out, "\n")
  end
  return d
end

local st = {
  name = frame.name, level = frame.level, why = frame.why or {},
  snap = { temp = frame.temp, flux = frame.flux, water = frame.water,
           steam = frame.steam, rodDepth = frame.rodDepth },
  cols = cols, grid = core.mergeGrid(grid),
  limits = core.mergeLimits({ tempScram = 1000, waterMin = 10 }),
  seq = frame.seq, stale = false,
}

do
  local D = fakeDisplay(160, 50)
  local view = { page = "map", param = skala.param("T"), cur = { x = 1, y = 1 },
                 series = {} }
  local L = ui.drawPane(D, st, view, { srcKind = "local", interactive = true })
  test("the panel lays out on a tier-3 screen", L.ok == true)

  -- The header names the reactor and its state.
  test("the header names the reactor",
    D.rowText(1):find("RBMK%-TEST") ~= nil)
  test("the header shows the level",
    D.rowText(1):find("OK") ~= nil)
  test("the header names the selected parameter, even though the rail also does",
    D.rowText(2):find("CORE TEMP") ~= nil)

  -- THE CELLS. This is what the whole chain exists to produce.
  local px, py = skala.cellPos(L, 7, 4, st.grid)
  eq("the cell for channel 7,4 shows its temperature", " 361",
    D.textAt(px, py, 4))
  local px2, py2 = skala.cellPos(L, 2, 1, st.grid)
  eq("the cell for channel 2,1 shows its temperature", " 317",
    D.textAt(px2, py2, 4))
  eq("...in the band colour for that reading",
    (skala.bandOf(317, skala.param("T"), st.limits)), D.colorAt(px2, py2))

  --! The inspection cursor is drawn INVERTED, so channel 1,1 -- which
  --! the cursor is on -- must NOT be in its band colour. Checking the
  --! neighbour above and the cursor here keeps the two apart; testing
  --! only one would let the cursor silently stop rendering.
  local cx1, cy1 = skala.cellPos(L, 1, 1, st.grid)
  eq("the cursor cell still shows its reading", " 310", D.textAt(cx1, cy1, 4))
  test("...but is inverted, so it is visibly the selected channel",
    D.colorAt(cx1, cy1) ~= D.colorAt(px2, py2))

  -- The rulers have to agree with the cells, or the map lies about
  -- which channel you are looking at.
  test("the column ruler numbers the columns",
    D.textAt(skala.cellPos(L, 7, 1, st.grid), L.rulerY, 4):find("7") ~= nil)
  test("the row ruler numbers the rows",
    D.textAt(1, skala.cellPos(L, 1, 4, st.grid) and L.mapY + 3, L.rulerW)
      :find("4") ~= nil)

  -- The rail.
  test("the rail lists every parameter",
    (function()
      local txt = D.screenText()
      for _, p in ipairs(skala.PARAMS) do
        if not txt:find(p.label, 1, true) then return false end
      end
      return true
    end)())

  -- The status line follows the cursor.
  test("the status line names the inspected channel",
    D.rowText(L.statusY + 1):find("ch 1,1") ~= nil)
  view.cur = { x = 7, y = 4 }
  ui.drawPane(D, st, view, { srcKind = "local", interactive = true })
  test("...and follows it when it moves",
    D.rowText(L.statusY + 1):find("ch 7,4") ~= nil)
  test("...reporting that channel's own reading, not the reactor's",
    D.rowText(L.statusY + 1):find("361") ~= nil)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- a hot channel is visibly hot --")
-- ══════════════════════════════════════════════════════════════════
do
  local D = fakeDisplay(160, 50)
  local ix = core.columnIndex(st.cols)
  ix["5,5"].temp = 1200        -- past the scram limit
  local view = { page = "map", param = skala.param("T"), cur = { x = 1, y = 1 },
                 series = {} }
  local L = ui.drawPane(D, st, view, {})
  local hx, hy = skala.cellPos(L, 5, 5, st.grid)
  local cx, cy = skala.cellPos(L, 5, 6, st.grid)
  eq("the hot channel reads 1200", "1200", D.textAt(hx, hy, 4))
  eq("...and is painted in the alarm colour", 0xFF0000, D.colorAt(hx, hy))
  test("...while its neighbour is not",
    D.colorAt(cx, cy) ~= 0xFF0000)
  ix["5,5"].temp = 300 + 35 + 15
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- a missing channel is not an empty one --")
-- ══════════════════════════════════════════════════════════════════
do
  --! A reading that dropped out must not shrink the visible core: an
  --! operator has to be able to tell "no data" from "no channel".
  local partial = {}
  for _, c in ipairs(st.cols) do
    if not (c.x == 9 and c.y == 9) then partial[#partial + 1] = c end
  end
  local st2 = {}
  for k, v in pairs(st) do st2[k] = v end
  st2.cols = partial
  local D = fakeDisplay(160, 50)
  local L = ui.drawPane(D, st2, { page = "map", param = skala.param("T"),
    cur = { x = 1, y = 1 }, series = {} }, {})
  local mx, my = skala.cellPos(L, 9, 9, st2.grid)
  eq("the unreported channel shows dashes, not blank", "----", D.textAt(mx, my, 4))
  eq("...in the missing colour, not a band colour",
    skala.COLOR_MISSING, D.colorAt(mx, my))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- a small screen degrades instead of failing --")
-- ══════════════════════════════════════════════════════════════════
do
  local D = fakeDisplay(50, 16)      -- too small for a 15x15 map
  local L = ui.drawPane(D, st, { page = "map", param = skala.param("T"),
    cur = { x = 1, y = 1 }, series = {} }, {})
  eq("the layout refuses", false, L.ok)
  local txt = D.screenText()
  test("...but the screen still names the reactor", txt:find("RBMK%-TEST") ~= nil)
  test("...and still shows the readings", txt:find("500") ~= nil)
  --! The refusal has to reach the operator, with the number that would
  --! fix it. "Too small" alone sends them away to guess.
  test("...and says what size it needs", txt:find("%d+") ~= nil
    and (txt:find("rows") ~= nil or txt:find("columns") ~= nil))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the reactor goes wrong --")
-- ══════════════════════════════════════════════════════════════════
do
  reactor.temp = 1200
  clock = clock + 1
  ticker()
  local f = core.decodeWire(table.unpack(sent[#sent].args, 1, sent[#sent].args.n))
  eq("the broadcast level goes to scram", "scram", f.level)
  test("...and carries the reason", f.why ~= nil and #f.why > 0)
  test("...naming the limit that tripped",
    f.why and f.why[1]:find("1000", 1, true) ~= nil)
  eq("the console was actually scrammed", true, reactor.scrammed)

  local hot = {}
  for k, v in pairs(st) do hot[k] = v end
  hot.level, hot.why = f.level, f.why
  hot.snap = { temp = f.temp }

  local D = fakeDisplay(160, 50)
  local L = ui.drawPane(D, hot, { page = "alarms", param = skala.param("T"),
    cur = { x = 1, y = 1 }, series = {} }, {})
  local txt = D.screenText()
  test("the alarm page shows the banner", txt:find("SCRAM") ~= nil)
  test("...and the reason", txt:find("scram limit") ~= nil)
  test("...and says the latch will not clear itself",
    txt:find("does not clear itself") ~= nil)

  -- Stale telemetry has to be louder than a level, because it means
  -- the numbers on screen are lies.
  local gone = {}
  for k, v in pairs(hot) do gone[k] = v end
  gone.stale, gone.level, gone.why = true, "ok", {}
  local D2 = fakeDisplay(160, 50)
  ui.drawPane(D2, gone, { page = "map", param = skala.param("T"),
    cur = { x = 1, y = 1 }, series = {} }, {})
  test("STALE outranks a level of 'ok' in the header",
    D2.rowText(1):find("STALE") ~= nil and D2.rowText(1):find("OK") == nil)

  reactor.temp = 500
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the operator commands --")
-- ══════════════════════════════════════════════════════════════════
--! The seam between the base image's `rbmk` stub and this library.
--! Every subcommand here is reachable with NO display, because the
--! stub's context argument is optional and a machine running `rbmk
--! status` from a script has no screen to hand over.
do
  local function capture(args, ctx)
    local lines = {}
    cmd.run(args, function(t) lines[#lines + 1] = tostring(t or "") end, ctx)
    return table.concat(lines, "\n")
  end

  local survey = capture({ "survey" })
  test("survey finds the console", survey:find("rbmk_console") ~= nil)
  test("...lists its real methods", survey:find("getColumnData") ~= nil)
  test("...shows what bound", survey:find("temp=getTemp") ~= nil)
  test("...names what did not", survey:find("missing") ~= nil
    and survey:find("fuel") ~= nil)
  test("...and says the binding is usable", survey:find("usable:%s+YES") ~= nil)
  --! The core map's accessor is reported SEPARATELY from the readings,
  --! because its absence is not a fault -- it costs the panel its
  --! per-channel grid and nothing else.
  test("...reporting the core map's accessor separately",
    survey:find("columns:") ~= nil and survey:find("SKALA core map") ~= nil)

  local limits = capture({ "limits" })
  test("limits prints the active values", limits:find("tempScram") ~= nil)
  test("...including the defaults that were not configured",
    limits:find("fluxScram") ~= nil)

  local status = capture({ "status" })
  test("status reads the reactor", status:find("500") ~= nil)
  test("...and states the level", status:find("OK") ~= nil)

  local w = capture({ "wall" }, { screen = { list = function()
    return { { index = 1 }, { index = 2 }, { index = 3 } }
  end } })
  test("wall lists a seat per screen", w:find("seat 3") ~= nil)
  test("...naming the page each would show", w:find("CORE MAP") ~= nil)
  test("...and says --wall is what drives them all", w:find("%-%-wall") ~= nil)
  --! The obvious question, answered on the spot: displays are absent
  --! from this listing on purpose, not by omission.
  test("...and explains why satellites are not listed",
    w:find("never register") ~= nil)

  --! Asking for the panel with no screen must be a sentence, not a
  --! nil-index crash inside a command.
  local noScreen = capture({ "skala" })
  test("the panel says it needs a screen rather than crashing",
    noScreen:find("needs a screen") ~= nil)

  local wDefault = capture({ "wall" })
  test("wall works with no screen module at all (assumes one seat)",
    wDefault:find("seat 1") ~= nil)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the controller stays one-way --")
-- ══════════════════════════════════════════════════════════════════
do
  --! Plan.md §Safety rule 1. The service must never open the telemetry
  --! port: broadcasting is one-way, but LISTENING would give an
  --! untrusted display a path into the machine that owns SCRAM.
  local opened = false
  local realOpen = modem.open
  modem.open = function() opened = true; return true end
  clock = clock + 1
  ticker()
  eq("the controller never opens the telemetry port", false, opened)
  modem.open = realOpen

  local src = io.open(LIB .. "rbmk-controld.lua", "rb"):read("*a")
  local stripped = src:gsub("%-%-[^\n]*", "")
  test("the daemon registers no network receive handler",
    stripped:find("event%.on") == nil and stripped:find("net%.on") == nil)
  test("...and does not call modem.open anywhere",
    stripped:find("%.open%s*%(") == nil)

  controld.stop()
  eq("the service stops", false, controld.running())
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
