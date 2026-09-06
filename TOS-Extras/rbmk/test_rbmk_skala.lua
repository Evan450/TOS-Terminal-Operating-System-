-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the SKALA panel + the display wall         ║
-- ║                                                              ║
-- ║  The drawing needs a GPU and is on the emulator checklist.   ║
-- ║  Everything the drawing DECIDES is arithmetic, and that is   ║
-- ║  what is proved here:                                        ║
-- ║                                                              ║
-- ║   • a cell is always exactly 4 characters, because a 5th     ║
-- ║     shifts every cell after it and the ruler stops meaning   ║
-- ║     anything;                                                ║
-- ║   • LOW COOLANT COLOURS AS ALARM. An inverted parameter      ║
-- ║     drawn on the normal ramp would make the wall calmest at  ║
-- ║     the moment it should be loudest — the single most        ║
-- ║     dangerous thing this panel could get wrong;              ║
-- ║   • a missing reading is MISSING, never the bottom band —    ║
-- ║     the same rule the safety logic already follows;          ║
-- ║   • a 15x15 core map FITS ONE 8 KB PACKET, which is the      ║
-- ║     constraint the whole packed wire format exists for       ║
-- ║     (Plan.md open question #2);                              ║
-- ║   • a SCRAM or stale telemetry takes the wall over, and a    ║
-- ║     mere warning does not;                                   ║
-- ║   • the OpenOS satellite's COPIED constants still match the  ║
-- ║     originals it cannot require.                             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua rbmk/test_rbmk_skala.lua   (from the TOS-Extras root)

local passed, failed = 0, 0

--! test() takes TWO arguments. A third would land in `cond` and every
--! such assertion would pass unconditionally -- which is exactly how
--! four dead tests once shipped green in this repo (test_blockfs.lua).
--! Making the harness refuse the mistake is cheaper than remembering
--! not to make it.
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

local base = ((arg and arg[0]) or "rbmk/test_rbmk_skala.lua"):gsub("[^/\\]*$", "")
package.path = "rbmk/controller-skeleton/usr/lib/?.lua;"
  .. "rbmk/controller-skeleton/usr/lib/?/init.lua;"
  .. base .. "controller-skeleton/usr/lib/?.lua;"
  .. base .. "controller-skeleton/usr/lib/?/init.lua;" .. package.path

local core  = require("rbmk.core")
local skala = require("rbmk.skala")
local wall  = require("rbmk.wall")

local LIMITS = core.mergeLimits({})

print("=== SKALA panel + display wall ===")
print()

-- ══════════════════════════════════════════════════════════════════
print("-- cell text is always four columns --")
-- ══════════════════════════════════════════════════════════════════
do
  local widths, worst = {}, nil
  for _, v in ipairs({ 0, 1, 9, 99, 999, 1000, 9999, 10000, 99999, 999999,
                       1e6, 1e9, 1e12, -1, -50, -999, -9999, -1e6, 0.4, 0.6 }) do
    local s = skala.cellText(v)
    widths[#widths + 1] = #s
    if #s ~= 4 then worst = v end
  end
  test("every magnitude renders in exactly 4 columns"
    .. (worst and (" -- " .. worst .. " did not") or ""), worst == nil)
  eq("nil is four dashes, not a zero", "----", skala.cellText(nil))
  eq("a non-number is four dashes", "----", skala.cellText("hot"))
  eq("NaN is four dashes", "----", skala.cellText(0 / 0))
  eq("rounds to nearest", " 513", skala.cellText(512.6))
  eq("thousands are scaled", " 12k", skala.cellText(12345))
  eq("negatives keep their sign", " -50", skala.cellText(-50))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- colour bands --")
-- ══════════════════════════════════════════════════════════════════
do
  local T, G = skala.param("T"), skala.param("G")
  test("parameters are found by letter, case-insensitively",
    skala.param("t") ~= nil and skala.param("t").key == "T")
  eq("an unknown letter is nil", nil, skala.param("Z"))

  -- The normal direction.
  eq("a cold core is 'cold'", "cold", select(2, skala.bandOf(10, T, LIMITS)))
  eq("mid-range is 'normal'", "normal", select(2, skala.bandOf(500, T, LIMITS)))
  eq("near the scram limit is 'alarm'", "alarm", select(2, skala.bandOf(1000, T, LIMITS)))
  eq("past the scram limit stays 'alarm'", "alarm", select(2, skala.bandOf(5000, T, LIMITS)))

  --! THE ONE THAT MATTERS. Coolant is inverted: 100% is healthy, and
  --! waterMin (10%) is the scram. Drawn on the normal ramp, a dry loop
  --! would render in the same calm blue as a cold core.
  eq("full coolant is calm", "cold", select(2, skala.bandOf(100, G, LIMITS)))
  eq("COOLANT AT THE MINIMUM IS ALARM", "alarm", select(2, skala.bandOf(10, G, LIMITS)))
  eq("COOLANT BELOW THE MINIMUM IS ALARM", "alarm", select(2, skala.bandOf(0, G, LIMITS)))
  test("a draining loop escalates rather than jumping",
    (function()
      local order = { cold = 1, normal = 2, high = 3, warn = 4, alarm = 5 }
      local last = 0
      for v = 100, 0, -5 do
        local rank = order[select(2, skala.bandOf(v, G, LIMITS))]
        if rank < last then return false end
        last = rank
      end
      return last == 5
    end)())

  -- Missing is its own thing.
  eq("a missing reading is 'missing', not 'cold'", "missing",
    select(2, skala.bandOf(nil, T, LIMITS)))
  eq("...and gets the missing colour", skala.COLOR_MISSING,
    (skala.bandOf(nil, T, LIMITS)))
  eq("a missing COOLANT reading is also 'missing'", "missing",
    select(2, skala.bandOf(nil, G, LIMITS)))

  -- The operator's own limit is the top of the scale.
  local tight = core.mergeLimits({ tempScram = 400 })
  eq("a lower scram limit makes 400 alarm", "alarm",
    select(2, skala.bandOf(400, T, tight)))
  eq("...where the default limit called it normal", "normal",
    select(2, skala.bandOf(400, T, LIMITS)))

  -- A nonsense inverted config must not divide by zero or flatten.
  local silly = core.mergeLimits({ waterMin = 10 })
  silly.waterMin = 500     -- above the healthy end: impossible
  local okBand = pcall(skala.bandOf, 50, G, silly)
  test("a nonsensical coolant minimum does not crash the ramp", okBand)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- core geometry --")
-- ══════════════════════════════════════════════════════════════════
do
  eq("a square core has every position", 225, skala.channelCount({ w = 15, h = 15 }))
  local circ = { w = 15, h = 15, shape = "circle" }
  test("a circular core has fewer, but not none",
    skala.channelCount(circ) < 225 and skala.channelCount(circ) > 100)
  test("the circle's centre is a channel", skala.isChannel(8, 8, circ))
  test("the circle's corner is not", not skala.isChannel(1, 1, circ))
  test("out of bounds is never a channel",
    not skala.isChannel(0, 5, circ) and not skala.isChannel(16, 5, circ))
  local masked = { w = 3, h = 3, mask = { ["2,2"] = true } }
  eq("an explicit mask overrides the shape", 1, skala.channelCount(masked))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- layout --")
-- ══════════════════════════════════════════════════════════════════
do
  local grid = { w = 15, h = 15 }
  local big = skala.layout(160, 50, grid)
  test("a tier-3 screen lays out", big.ok == true)
  eq("...with full numeric cells", true, big.numeric)
  test("...and the comfortable rail", big.railW == skala.RAIL_PREF)
  test("the map starts right of the row ruler", big.mapX > big.rulerW)
  test("the rail does not overlap the map",
    big.railX > big.mapX + grid.w * big.cellW - 1)
  test("the status row is below the map",
    big.statusY >= big.mapY + grid.h)
  test("everything fits on the screen", big.statusY + 1 <= big.H)

  --! Degradation order: numbers survive before the menu does.
  local mid = skala.layout(80, 25, grid)
  test("an 80-column screen still lays out", mid.ok == true)
  eq("...and KEEPS THE NUMBERS by dropping the rail", true, mid.numeric)
  eq("...so there is no rail at 80 columns", nil, mid.railX)

  local short = skala.layout(160, 12, grid)
  eq("too few rows is refused", false, short.ok)
  test("...and the refusal names the rows needed",
    type(short.why) == "string" and short.why:find("21", 1, true) ~= nil)
  local narrow = skala.layout(20, 50, grid)
  eq("too few columns is refused", false, narrow.ok)
  test("...and the refusal names the columns needed",
    type(narrow.why) == "string" and narrow.why:find("%d+$") ~= nil)

  -- A small core fits a small screen: the refusal must be about the
  -- core, not a hard-coded minimum screen size.
  local tiny = skala.layout(50, 16, { w = 5, h = 5 })
  test("a 5x5 core fits where a 15x15 core did not", tiny.ok == true)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- cell hit-testing --")
-- ══════════════════════════════════════════════════════════════════
do
  local grid = { w = 15, h = 15 }
  local L = skala.layout(160, 50, grid)
  local bad = 0
  for y = 1, 15 do
    for x = 1, 15 do
      local px, py = skala.cellPos(L, x, y, grid)
      local bx, by = skala.cellAt(L, px, py, grid)
      if bx ~= x or by ~= y then bad = bad + 1 end
    end
  end
  test("every cell round-trips position -> hit-test (" .. bad .. " bad)", bad == 0)

  --! The separator column belongs to no cell. Without this an operator
  --! clicking the gap silently inspects the channel to its LEFT.
  local px = skala.cellPos(L, 3, 3, grid)
  eq("the gap after a cell is not that cell", nil,
    (skala.cellAt(L, px + 4, L.mapY + 2, grid)))
  eq("...but the last character of the cell is", 3,
    (skala.cellAt(L, px + 3, L.mapY + 2, grid)))
  eq("above the map is nothing", nil, (skala.cellAt(L, L.mapX, L.mapY - 1, grid)))
  eq("below the map is nothing", nil,
    (skala.cellAt(L, L.mapX, L.mapY + grid.h, grid)))
  eq("left of the map is nothing", nil, (skala.cellAt(L, 1, L.mapY, grid)))
  eq("right of the last column is nothing", nil,
    (skala.cellAt(L, L.mapX + grid.w * L.cellW + 1, L.mapY, grid)))

  local circ = { w = 15, h = 15, shape = "circle" }
  local Lc = skala.layout(160, 50, circ)
  local cx = skala.cellPos(Lc, 8, 8, circ)
  test("a circular core still hit-tests at its centre",
    (skala.cellAt(Lc, cx, Lc.mapY + 7, circ)) == 8)
  eq("...and a corner outside the circle is not clickable", nil,
    (skala.cellAt(Lc, Lc.mapX, Lc.mapY, circ)))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the packed core map --")
-- ══════════════════════════════════════════════════════════════════
do
  local grid = core.mergeGrid({})
  eq("the default grid is 15x15", 15, grid.w)

  local cols = {}
  for y = 1, 15 do
    for x = 1, 15 do
      cols[#cols + 1] = { x = x, y = y,
        kind = (x % 3 == 0) and "control" or "fuel",
        temp = 300 + x * 7 + y * 3, flux = 1000 + x * 100,
        steam = 40, rodDepth = 50, water = 90 }
    end
  end
  local packed = core.packColumns(cols, grid, skala.PARAMS)

  --! Plan.md open question #2, answered with a number. This is the
  --! whole reason the map is a packed string instead of a table: the
  --! same data as plain Lua tables serialises to roughly 12 KB, and
  --! protocol.MAX_SIZE -- the OC modem's own ceiling -- is 8192.
  test(string.format("a FULL 15x15 core map packs to %d bytes (limit 8192)", #packed),
    #packed < 8192)
  local frame = core.frame({ temp = 500 }, "warn", 9, 40, "rbmk-1", packed,
    { "core 900 >= warn limit 800" })
  local wire = core.encodeWire(frame)
  local total = 0
  for _, a in ipairs(wire) do total = total + #tostring(a) end
  test(string.format("...and the whole wire frame is %d bytes (limit 8192)", total),
    total < 8192)

  local back, g2 = core.unpackColumns(packed, skala.PARAMS)
  eq("every channel comes back", 225, back and #back)
  eq("the grid width survives", 15, g2 and g2.w)
  local ix = core.columnIndex(back)
  eq("a channel's kind survives", "control", ix["6,2"] and ix["6,2"].kind)
  eq("a channel's kind survives (fuel)", "fuel", ix["7,4"] and ix["7,4"].kind)
  eq("temperature survives exactly at step 1", 300 + 49 + 12, ix["7,4"].temp)
  test("flux survives to within its quantisation step",
    math.abs(ix["7,4"].flux - 1700) <= 4)

  -- A sparse core: absent positions must stay absent.
  local circ = core.mergeGrid({ shape = "circle" })
  local ccols = {}
  for y = 1, 15 do
    for x = 1, 15 do
      if skala.isChannel(x, y, circ) then
        ccols[#ccols + 1] = { x = x, y = y, kind = "fuel", temp = 500 }
      end
    end
  end
  local cpacked = core.packColumns(ccols, circ, skala.PARAMS)
  local cback = core.unpackColumns(cpacked, skala.PARAMS)
  eq("a sparse core round-trips with the same channel count",
    #ccols, cback and #cback)
  eq("...and the corner stays absent", nil, core.columnIndex(cback)["1,1"])

  -- Missing readings must stay missing, not become zero.
  local sparse = core.packColumns({ { x = 1, y = 1, kind = "fuel" } },
    { w = 1, h = 1 }, skala.PARAMS)
  local sb = core.unpackColumns(sparse, skala.PARAMS)
  eq("a channel with no temperature comes back with no temperature",
    nil, sb[1].temp)

  --! SATURATION, not wrap-around. A base-36 triple holds 0..46655; a
  --! reading above that has to come back pinned at the TOP. If it
  --! wrapped, an over-range channel would decode to a LOW number and
  --! the wall would draw a runaway channel in calm blue -- the same
  --! class of failure as the inverted-coolant ramp, arriving by
  --! arithmetic instead of by colour.
  local function trip(field, value, step)
    local p = core.packColumns({ { x = 1, y = 1, kind = "fuel", [field] = value } },
      { w = 1, h = 1 }, skala.PARAMS)
    local b = core.unpackColumns(p, skala.PARAMS)
    return b and b[1] and b[1][field], 46655 * step
  end
  local hot, maxTemp = trip("temp", 60000, 1)
  eq("an over-range temperature saturates at the top", maxTemp, hot)
  test("...it does NOT wrap to a low value", hot ~= nil and hot > 40000)
  local blaze, maxFlux = trip("flux", 5e6, 4)
  eq("an over-range flux saturates at the top", maxFlux, blaze)
  test("...it does NOT wrap to a low value", blaze ~= nil and blaze > 100000)
  --! The bottom clamp is documented, not accidental: the wire form
  --! carries no sign, so a negative reading floors at zero. Nothing
  --! safety-critical reads this path -- evaluate() runs on the
  --! controller's own raw value.
  eq("a negative reading floors at zero rather than wrapping high",
    0, (trip("temp", -50, 1)))

  -- Malformed input returns nil; it must never throw inside a redraw.
  for _, bad in ipairs({ "", "hello", "2", "2;15,15", "2;15,15;short",
                         "2;0,0;", "2;99,99;x", "2;2,1;FF;Tabcd",
                         "1;15,15;" .. string.rep("F", 225) }) do
    local ok, res = pcall(core.unpackColumns, bad, skala.PARAMS)
    test("malformed map (" .. bad:sub(1, 14) .. ") returns nil, never throws",
      ok and res == nil)
  end
  test("a non-string map is refused", (core.unpackColumns(nil, skala.PARAMS)) == nil)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the telemetry wire --")
-- ══════════════════════════════════════════════════════════════════
do
  eq("the telemetry port is off the cluster and rc-pilot ports",
    2200, core.TELEMETRY_PORT)
  local f = core.frame({ temp = 512.5, flux = 3000, water = 88 }, "warn", 42, 99,
    "rbmk-1", nil, { "core 900 >= warn limit 800" })
  local wire = core.encodeWire(f)
  eq("the wire is a fixed argument count", core.WIRE_ARGS, #wire)
  eq("the first argument is the magic", "RBMK", wire[1])
  for i, a in ipairs(wire) do
    test("argument " .. i .. " is a primitive, never a table",
      type(a) == "string" or type(a) == "number")
  end

  local back = core.decodeWire(table.unpack(wire, 1, core.WIRE_ARGS))
  test("a frame survives the wire", back ~= nil)
  eq("the name survives", "rbmk-1", back.name)
  eq("the sequence survives", 42, back.seq)
  eq("the level survives", "warn", back.level)
  eq("the temperature survives", 512.5, back.temp)
  eq("a reason survives", "core 900 >= warn limit 800", back.why and back.why[1])
  eq("an unreported reading stays unreported", nil, back.steam)

  eq("a short argument list is refused", nil,
    (core.decodeWire("RBMK", 2, "x", 1)))
  eq("someone else's broadcast is refused", nil,
    (core.decodeWire("HTTP", 2, "x", 1, 0, "ok", "", "", "")))
  eq("an unsupported version is refused", nil,
    (core.decodeWire("RBMK", 99, "x", 1, 0, "ok", "", "", "")))
  eq("a frame with no sequence is refused", nil,
    (core.decodeWire("RBMK", 2, "x", "no", 0, "ok", "", "", "")))

  --! A scalar run is attacker-controlled text. Only known keys may
  --! become fields: otherwise a broadcast could introduce arbitrary
  --! names into the table the renderer indexes.
  local sneaky = core.decodeWire("RBMK", 2, "x", 1, 0, "ok",
    "temp=500,scram=1,exec=9,rod=3", "", "")
  test("a scalar run cannot smuggle in a control field",
    sneaky ~= nil and sneaky.scram == nil and sneaky.exec == nil
      and sneaky.rod == nil and sneaky.temp == 500)

  -- The read-only guarantee, restated at the frame validator.
  for _, bad in ipairs({ "cmd", "command", "setRod", "rod", "scram", "exec" }) do
    local hostile = core.frame({ temp = 1 }, "ok", 1, 1)
    hostile[bad] = true
    eq("a frame carrying '" .. bad .. "' is refused", false,
      (core.validateFrame(hostile)))
  end
  local badCols = core.frame({ temp = 1 }, "ok", 1, 1)
  badCols.cols = { "not a string" }
  eq("a non-string core map is refused", false, (core.validateFrame(badCols)))
  local badWhy = core.frame({ temp = 1 }, "ok", 1, 1)
  badWhy.why = { {} }
  eq("a reason list holding a table is refused", false, (core.validateFrame(badWhy)))

  -- The reason list is bounded, because the packet is.
  local many = {}
  for i = 1, 50 do many[i] = "reason " .. i end
  local capped = core.frame({ temp = 1 }, "scram", 1, 1, "r", nil, many)
  test("the reason list is capped at MAX_REASONS",
    #capped.why == core.MAX_REASONS)

  -- v1 satellites are still accepted.
  local old = { magic = "RBMK", v = 1, seq = 1 }
  eq("a v1 frame still validates", true, (core.validateFrame(old)))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- grid config --")
-- ══════════════════════════════════════════════════════════════════
do
  local ok = core.mergeGrid({ w = 9, h = 9, shape = "circle" })
  eq("an operator grid is honoured", 9, ok.w)
  eq("...including the shape", "circle", ok.shape)
  --! Same posture as mergeLimits: a typo falls back to the DEFAULT,
  --! never to something degenerate that cannot be drawn.
  eq("a zero width falls back to the default", 15, core.mergeGrid({ w = 0 }).w)
  eq("a negative height falls back", 15, core.mergeGrid({ h = -3 }).h)
  eq("a fractional width falls back", 15, core.mergeGrid({ w = 7.5 }).w)
  eq("an absurd width falls back", 15, core.mergeGrid({ w = 9999 }).w)
  eq("a nonsense shape falls back to square", "square",
    core.mergeGrid({ shape = "trapezoid" }).shape)
  eq("a non-table config is fine", 15, core.mergeGrid("nope").w)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the display wall --")
-- ══════════════════════════════════════════════════════════════════
local validParam = function(k) return skala.param(k) ~= nil end
do
  local p = wall.plan(4, nil, validParam)
  eq("four screens get four panes", 4, #p)
  eq("seat 1 is the core map", "map", p[1].page)
  test("no two adjacent seats show the same page", p[1].page ~= p[2].page)
  local seen = {}
  for _, q in ipairs(p) do seen[q.page] = true end
  test("a four-screen wall shows four different pages",
    seen.map and seen.panel and seen.alarms and seen.trend)
  eq("zero screens is not an error", 0, #wall.plan(0, nil, validParam))
  eq("a negative count is not an error", 0, #wall.plan(-1, nil, validParam))

  local eight = wall.plan(8, nil, validParam)
  eq("more screens than pages still assigns every one", 8, #eight)
  local blank = 0
  for _, q in ipairs(eight) do if not wall.page(q.page) then blank = blank + 1 end end
  eq("...and none is left blank", 0, blank)

  -- Operator config.
  local cfg = { [2] = { page = "trend", param = "N", pinned = true } }
  local c = wall.plan(3, cfg, validParam)
  eq("a configured page is used", "trend", c[2].page)
  eq("...with its parameter", "N", c[2].param)
  eq("...and its pin", true, c[2].pinned)
  eq("unconfigured seats keep the rotation", "map", c[1].page)

  --! A typo must not turn a screen off, and must be REPORTED: a
  --! display silently showing something other than what was asked for
  --! is how a wall lies to the room it is in.
  local typo = wall.plan(2, { [1] = { page = "trned", param = "Q" } }, validParam)
  test("a misspelled page falls back to a real one", wall.page(typo[1].page) ~= nil)
  test("a misspelled parameter falls back to a real one",
    skala.param(typo[1].param) ~= nil)
  eq("...and the fallback is recorded so `rbmk wall` can say so",
    true, typo[1].rejected)
  eq("a good config is not marked rejected", nil,
    wall.plan(1, { [1] = { page = "alarms" } }, validParam)[1].rejected)
end

do
  local panes = wall.plan(4, { [3] = { page = "trend", pinned = true } }, validParam)

  -- Normal running: nobody is overridden.
  local e, ov = wall.effective(panes, "ok", false)
  eq("a healthy reactor does not seize the wall", false, ov)
  eq("...and the panes are untouched", "map", e[1].page)

  --! A warning is advisory and happens in normal operation. A wall
  --! that seized every screen on every advisory would train the room
  --! to ignore it, which is the same as not having it.
  local ew, ovw = wall.effective(panes, "warn", false)
  eq("a WARNING does not seize the wall", false, ovw)
  eq("...panes still show their own pages", "map", ew[1].page)

  local es, ovs, why = wall.effective(panes, "scram", false)
  eq("a SCRAM seizes the wall", true, ovs)
  eq("...and says why", "SCRAM", why)
  eq("seat 1 switches to alarms", "alarms", es[1].page)
  eq("seat 2 switches to alarms", "alarms", es[2].page)
  eq("A PINNED SEAT KEEPS ITS PAGE", "trend", es[3].page)
  eq("...and is not marked overridden", nil, es[3].overridden)
  eq("an overridden pane records the reason", "SCRAM", es[1].overridden)

  local et, ovt, whyt = wall.effective(panes, "ok", true)
  eq("STALE telemetry seizes the wall even at level ok", true, ovt)
  eq("...and says so", "TELEMETRY STALE", whyt)
  eq("...on every unpinned seat", "alarms", et[2].page)

  test("the override does not mutate the plan it was given",
    panes[1].page == "map" and panes[1].overridden == nil)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- trend series --")
-- ══════════════════════════════════════════════════════════════════
do
  local s = {}
  for i = 1, 10 do s = wall.push(s, i * 10, 120) end
  local lo, hi, n = wall.range(s)
  eq("range finds the low", 10, lo)
  eq("range finds the high", 100, hi)
  eq("range counts the samples", 10, n)

  s = wall.push(s, nil, 120)
  local _, _, n2 = wall.range(s)
  eq("A GAP IS NOT COUNTED AS A SAMPLE", 10, n2)
  eq("...but it does occupy a slot", 11, #s)

  local capped = {}
  for i = 1, 500 do capped = wall.push(capped, i, 60) end
  eq("the ring is bounded", 60, #capped)
  eq("...keeping the NEWEST samples", 500, capped[#capped])

  local sp = wall.spark(s, 11, lo, hi)
  eq("a sparkline is one character per sample", 11, #({ sp:gsub("[\128-\191]", "") })[1])
  test("A GAP RENDERS AS BLANK, not as a low reading",
    sp:sub(-1) == " ")

  local flat = {}
  for _ = 1, 5 do flat = wall.push(flat, 42, 60) end
  local fl, fh = wall.range(flat)
  test("a flat series draws mid-height, not at zero or full",
    wall.spark(flat, 5, fl, fh) == string.rep(wall.SPARK[5], 5))

  local rows = wall.chart({ 1, 5, 10 }, 3, 4, 1, 10)
  eq("a chart has one row per height", 4, #rows)
  test("the top row shows only the tallest bar",
    rows[1]:sub(1, 1) == " " and rows[1]:sub(3, 3) ~= " ")
  test("the bottom row shows every bar", not rows[4]:find(" ", 1, true))
  --! A real sample must always draw at least one row: a zero-height
  --! bar is indistinguishable from a gap, and those mean opposite
  --! things.
  local zr = wall.chart({ 0, 10 }, 2, 5, 0, 10)
  test("the smallest real sample still draws a bar",
    zr[5]:sub(1, 1) ~= " ")
  local gaps = wall.chart({ false, 10 }, 2, 5, 0, 10)
  test("...but a GAP draws nothing at all",
    gaps[5]:sub(1, 1) == " ")
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the readout --")
-- ══════════════════════════════════════════════════════════════════
do
  local snap = { temp = 520, flux = 3000, steam = 40, rodDepth = 50, water = 88 }
  local r = skala.readout(snap, nil, skala.param("T"), LIMITS)
  eq("the readout covers every parameter", #skala.PARAMS, #r)
  local sel = 0
  for _, row in ipairs(r) do if row.selected then sel = sel + 1 end end
  eq("exactly one row is marked selected", 1, sel)

  -- A selected channel takes precedence over the reactor-wide reading.
  local chan = { temp = 999 }
  local rc = skala.readout(snap, chan, skala.param("T"), LIMITS)
  test("a selected channel's reading is what is shown",
    rc[2].text:find("999", 1, true) ~= nil)
  test("...and a reading the channel lacks reads as missing, not the reactor's",
    rc[1].text:find("----", 1, true) ~= nil)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the OpenOS satellite's copied constants --")
-- ══════════════════════════════════════════════════════════════════
--! The satellite cannot require any of the above: OpenOS does not
--! speak the TOS protocol and has none of these libraries. So it
--! carries copies, and copies drift. This is the same guard pane-ui
--! uses for its copy of the TOS glyph table.
do
  local src
  for _, pre in ipairs({ "rbmk/", base, "" }) do
    local h = io.open(pre .. "openos/rbmk-display.lua", "rb")
    if h then src = h:read("*a"); h:close(); break end
  end
  test("the satellite is readable", src ~= nil)

  if src then
    local function grab(name)
      local body = src:match("local " .. name .. "%s*=%s*(%b{})")
      if not body then return nil end
      local chunk = load("return " .. body, "=" .. name, "t", {})
      if not chunk then return nil end
      local ok, res = pcall(chunk)
      return ok and res or nil
    end

    local sp = grab("PARAMS")
    test("the satellite's PARAMS table parses", type(sp) == "table")
    if type(sp) == "table" then
      eq("the satellite has the same number of parameters", #skala.PARAMS, #sp)
      local mismatch = {}
      for i, p in ipairs(skala.PARAMS) do
        local q = sp[i] or {}
        for _, f in ipairs({ "key", "label", "field", "unit",
                             "full", "limit", "invert", "step" }) do
          if p[f] ~= q[f] then
            mismatch[#mismatch + 1] = (p.key or i) .. "." .. f
          end
        end
      end
      test("EVERY parameter field matches the controller's"
        .. (#mismatch > 0 and (" -- differs: " .. table.concat(mismatch, ", ")) or ""),
        #mismatch == 0)
    end

    local sb = grab("BANDS")
    test("the satellite's BANDS table parses", type(sb) == "table")
    if type(sb) == "table" then
      local bad = {}
      for i, b in ipairs(skala.BANDS) do
        local c = sb[i] or {}
        if b[1] ~= c[1] or b[2] ~= c[2] or b[3] ~= c[3] then
          bad[#bad + 1] = tostring(b[3])
        end
      end
      eq("the satellite has the same number of bands", #skala.BANDS, #sb)
      test("EVERY colour band matches the controller's"
        .. (#bad > 0 and (" -- differs: " .. table.concat(bad, ", ")) or ""),
        #bad == 0)
    end

    local port = tonumber(src:match("local DEFAULT_PORT%s*=%s*(%d+)"))
    eq("the satellite listens on the port the controller broadcasts on",
      core.TELEMETRY_PORT, port)
    local nargs = tonumber(src:match("local WIRE_ARGS%s*=%s*(%d+)"))
    eq("the satellite expects the argument count the controller sends",
      core.WIRE_ARGS, nargs)
    local miss = tonumber(src:match("local COLOR_MISSING%s*=%s*(0x%x+)")
      or src:match("local COLOR_MISSING%s*=%s*(%d+)"))
    eq("the satellite's missing colour matches", skala.COLOR_MISSING, miss)
    eq("the satellite's absent-cell character matches",
      core.KIND_ABSENT, src:match('local KIND_ABSENT%s*=%s*"(.-)"'))

    -- The satellite's own copy of the refusal list.
    local forb = grab("FORBIDDEN")
    test("the satellite refuses the same control fields",
      type(forb) == "table" and #forb == 6)

    -- Every kind the controller can EMIT must have a name on the
    -- satellite, or a channel decodes to an unlabelled kind.
    local kn = grab("KIND_NAME")
    if type(kn) == "table" then
      local unknown = {}
      for name, ch in pairs(core.KINDS) do
        if kn[ch] ~= name then unknown[#unknown + 1] = name end
      end
      test("every column kind the controller emits has a satellite name"
        .. (#unknown > 0 and (" -- missing: " .. table.concat(unknown, ", ")) or ""),
        #unknown == 0)
    else
      test("the satellite's KIND_NAME table parses", false)
    end

    --! Matching CONSTANTS is not enough. The satellite reimplements the
    --! colour ramp and the cell formatter, and either could drift while
    --! every constant above still matched. So the copied FUNCTIONS are
    --! lifted out of the file, run in an empty environment against the
    --! controller's own, and compared over a sweep of real values.
    --! (A satellite that formats -9999 five characters wide shifts its
    --! whole core map -- which is the bug this suite just caught in the
    --! controller's copy.)
    local function grabFn(name, params, env)
      local body = src:match("\nlocal function " .. name
        .. "%(" .. params .. "%)\n(.-)\nend\n")
      if not body then return nil end
      local chunk = load("return function(" .. params .. ")\n" .. body .. "\nend",
        "=" .. name, "t", env)
      if not chunk then return nil end
      local ok, fn = pcall(chunk)
      return ok and fn or nil
    end

    local env = { string = string, math = math, type = type, ipairs = ipairs,
                  tonumber = tonumber, tostring = tostring }
    local satCell = grabFn("cellText", "v", env)
    test("the satellite's cellText lifts out of the file", satCell ~= nil)
    if satCell then
      local diff = {}
      for _, v in ipairs({ 0, 1, 250, 999, 1000, 5000, 9999, 10000, 12345,
                           99999, 999999, 1e6, 1e9, -1, -50, -999, -1000,
                           -9999, -50000, -1e6, 0.4, 512.6 }) do
        if satCell(v) ~= skala.cellText(v) then diff[#diff + 1] = tostring(v) end
      end
      test("the satellite formats every cell exactly as the controller does"
        .. (#diff > 0 and (" -- differs at " .. table.concat(diff, ", ")) or ""),
        #diff == 0)
      eq("...including a missing reading", "----", satCell(nil))
      local wide = 0
      for _, v in ipairs({ -9999, -1000, 9999, 12345, 1e9 }) do
        if #satCell(v) ~= 4 then wide = wide + 1 end
      end
      eq("...and never renders a cell wider than 4 columns", 0, wide)
    end

    env.PARAMS, env.BANDS = sp, sb
    env.COLOR_MISSING = skala.COLOR_MISSING
    env.LIMITS = grab("LIMITS")
    env.fractionOf = grabFn("fractionOf", "value, p", env)
    local satBand = grabFn("bandOf", "value, p", env)
    test("the satellite's bandOf lifts out of the file", satBand ~= nil)
    if satBand and sp then
      --! Compared against the DEFAULT limits, because that is what the
      --! satellite hard-codes: it has no /etc/rbmk.cfg to read.
      local diff = {}
      for i, p in ipairs(skala.PARAMS) do
        for _, v in ipairs({ nil, 0, 5, 10, 50, 100, 400, 800, 1000,
                             5000, 10000, 20000 }) do
          local a = select(2, satBand(v, sp[i]))
          local b = select(2, skala.bandOf(v, p, LIMITS))
          if a ~= b then
            diff[#diff + 1] = p.key .. "@" .. tostring(v) .. " " .. tostring(a)
              .. "~=" .. tostring(b)
          end
        end
      end
      test("the satellite bands every reading exactly as the controller does"
        .. (#diff > 0 and (" -- " .. table.concat(diff, ", ", 1,
            math.min(4, #diff))) or ""),
        #diff == 0)
      --! Restated on the satellite specifically, because this is the
      --! copy an operator is most likely to be looking at.
      eq("LOW COOLANT IS ALARM ON THE SATELLITE TOO", "alarm",
        select(2, satBand(5, sp[5])))
      eq("...and a missing reading is still 'missing' there", "missing",
        select(2, satBand(nil, sp[2])))
    end

    --! The satellite is a DISPLAY. It must never transmit: a broadcast
    --! from an untrusted pane is the inbound path Plan.md §Safety rule
    --! 1 exists to deny.
    local stripped = src:gsub("%-%-[^\n]*", "")
    test("the satellite never broadcasts",
      stripped:find("%.broadcast") == nil)
    test("the satellite never sends",
      stripped:find("%.send%s*%(") == nil)
    test("the satellite opens the telemetry port",
      stripped:find("%.open%s*%(") ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
