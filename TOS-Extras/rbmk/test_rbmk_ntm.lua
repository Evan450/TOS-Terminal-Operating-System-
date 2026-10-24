-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the NTM console driver (hbm-ntm)           ║
-- ║                                                              ║
-- ║  Plan.md's open question #1 ("what does HBM's RBMK console   ║
-- ║  actually expose?") was answered by reading the mod's own    ║
-- ║  bytecode: component `rbmk_console`, getColumnData(x, y) per ║
-- ║  channel, pressAZ5() to shut down. This proves the add-on    ║
-- ║  uses that surface correctly.                                ║
-- ║                                                              ║
-- ║  The fake console is shaped like the REAL reply — same keys, ║
-- ║  same units, nil where there is no channel — because a fake  ║
-- ║  that returns what the code hopes to see tests nothing. It   ║
-- ║  cannot prove the mod behaves this way in a world; it can    ║
-- ║  prove that if it does, the numbers come out right and the   ║
-- ║  failure cases (unlinked console, dead channel, rods that    ║
-- ║  will not move) are loud instead of silent.                  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua rbmk/test_rbmk_ntm.lua   (from the TOS-Extras root)

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
local function has(s, sub) return type(s) == "string" and s:find(sub, 1, true) ~= nil end
local function near(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ", want ~" .. tostring(expected) .. ")",
    type(actual) == "number" and math.abs(actual - expected) < 1e-6)
end

local base = ((arg and arg[0]) or "rbmk/test_rbmk_ntm.lua"):gsub("[^/\\]*$", "")
local LIB = base .. "controller-skeleton/usr/lib/"
package.path = "rbmk/controller-skeleton/usr/lib/?.lua;"
  .. "rbmk/controller-skeleton/usr/lib/?/init.lua;"
  .. LIB .. "?.lua;" .. LIB .. "?/init.lua;" .. package.path

print("=== RBMK NTM console driver ===")
print()

-- ══════════════════════════════════════════════════════════════════
-- A core, in the shape getColumnData really returns
-- ══════════════════════════════════════════════════════════════════
-- Console coordinates, 0..14. Key names are the ones the mod writes
-- (hullTemp, coreTemp, coreMaxTemp, fluxQuantity, level, water, steam,
-- enrichment, ...); fuel temperatures are absolute, the boiler's tanks
-- are in mB, a control rod's `level` is 0 = fully inserted.
local function fuel(hull, core, coreMax, enr, flux)
  return { type = "FUEL", hullTemp = hull, realSimWater = 0, realSimSteam = 0,
           moderated = true, enrichment = enr, xenon = 0.01,
           coreSkinTemp = hull, coreTemp = core, coreMaxTemp = coreMax,
           fluxQuantity = flux, fluxRatio = 0.5 }
end
local function control(level)
  return { type = "CONTROL", hullTemp = 280, realSimWater = 0, realSimSteam = 0,
           moderated = false, level = level, color = 2 }
end
local function boiler(water, steam)
  return { type = "BOILER", hullTemp = 350, realSimWater = water, realSimSteam = steam,
           moderated = false, water = water, steam = steam }
end

local function newCore()
  return {
    ["6,6"] = fuel(400, 1000, 2000, 0.8, 100),
    ["8,6"] = fuel(500, 1400, 2000, 0.6, 120),   -- 70 % of melting point
    ["6,8"] = fuel(450, 1200, 2000, 0.4, 80),
    ["8,8"] = fuel(300,  600, 2000, 1.0, 100),
    ["7,6"] = control(1.0),                      -- fully withdrawn
    ["7,8"] = control(0.2),                      -- 80 % inserted
    ["5,7"] = boiler(4000, 250000),              -- 40 % water, 25 % steam
    ["9,7"] = boiler(8000, 750000),              -- 80 % water, 75 % steam
    ["7,7"] = { type = "MODERATOR", hullTemp = 200, realSimWater = 0,
                realSimSteam = 0, moderated = false },
  }
end

local core = require("rbmk.core")

-- ══════════════════════════════════════════════════════════════════
print("-- binding the real surface --")
-- ══════════════════════════════════════════════════════════════════
do
  local profile = core.PROFILES["hbm-ntm"]
  test("the hbm-ntm profile ships", type(profile) == "table")
  eq("it targets the component the mod registers", "rbmk_console",
    profile.componentTypes[1])

  local real = { "getColumnData", "getRBMKPos", "setLevel", "setColumnLevel",
                 "setColorLevel", "setColor", "pressAZ5", "type", "address" }
  local b = core.bind(profile, real)
  eq("every reading binds to getColumnData", "getColumnData", b.bound.temp)
  eq("...including coolant", "getColumnData", b.bound.water)
  eq("SCRAM binds to pressAZ5", "pressAZ5", b.bound.scram)
  eq("the core map's accessor is the same call", "getColumnData", b.columns)
  eq("the link check is found", "getRBMKPos", b.pos)
  eq("nothing is missing", 0, #b.missing)
  eq("the binding is usable", true, (core.bindingUsable(b, false)))

  local set = core.bind(profile, { getColumnData = true, pressAZ5 = true })
  eq("set-form method lists bind too", "pressAZ5", set.bound.scram)

  local noScram = core.bind(profile, { "getColumnData" })
  eq("without pressAZ5 the SCRAM is reported missing", "pressAZ5", noScram.missing[1])
  eq("...and the binding is refused", false, (core.bindingUsable(noScram, false)))
  eq("...unless the redstone AZ-5 line stands in", true,
    (core.bindingUsable(noScram, true)))

  local noData = core.bind(profile, { "pressAZ5" })
  eq("without getColumnData nothing can be read", "getColumnData", noData.missing[1])
  local ok, why = core.bindingUsable(noData, true)
  eq("...and not even a redstone line makes that supervisable", false, ok)
  test("...and it says it is blind", has(why, "temperature"))

  eq("a console with neither reports both", 2, #core.bind(profile, {}).missing)

  --! The old guessed names must not leak into the real driver: a console
  --! that happens to have a getTemp is not thereby readable.
  local decoy = core.bind(profile, { "getTemp", "setAZ5" })
  eq("guessed getter names do not bind", false, (core.bindingUsable(decoy, false)))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- folding the channels into readings --")
-- ══════════════════════════════════════════════════════════════════
do
  local c = newCore()
  local calls = 0
  local snap, cols, stats = core.scanCore(function(x, y)
    calls = calls + 1
    return c[x .. "," .. y]
  end)

  eq("the whole 15x15 console frame is scanned", 225, calls)
  eq("nine channels exist", 9, #cols)
  eq("all nine were read", 9, stats.read)
  eq("none failed", 0, snap.unread)

  eq("temp is the hottest hull anywhere", 500, snap.temp)
  near("melt is the hottest rod as a % of its OWN melting point", 70, snap.melt)
  eq("flux is the sum over the rods", 400, snap.flux)
  near("rod depth is the mean insertion (levels 1.0 and 0.2)", 40, snap.rodDepth)
  near("coolant is the LOWEST boiler, not the mean", 40, snap.water)
  near("steam is the mean of the boilers", 50, snap.steam)
  near("fuel is the mean enrichment as a percent", 70, snap.fuel)

  local ix = core.columnIndex(cols)
  local hot = ix["9,7"]            -- console (8,6) -> 1-based (9,7)
  test("channels are 1-based on the map", hot ~= nil)
  eq("a fuel channel is kind fuel", "fuel", hot and hot.kind)
  eq("...with its hull temperature", 500, hot and hot.temp)
  near("...and its own melt percentage", 70, hot and hot.melt)
  eq("a control rod is kind control", "control", ix["8,7"] and ix["8,7"].kind)
  near("...and shows insertion, not level (level 0.2 -> 80)", 80, ix["8,9"] and ix["8,9"].rodDepth)
  near("...fully withdrawn (level 1.0) is 0 inserted", 0, ix["8,7"] and ix["8,7"].rodDepth)
  eq("a boiler is kind boiler", "boiler", ix["6,8"] and ix["6,8"].kind)
  near("...with its coolant as a percent of 10000 mB", 40, ix["6,8"] and ix["6,8"].water)
  near("...and its steam as a percent of 1,000,000 mB", 25, ix["6,8"] and ix["6,8"].steam)
  eq("a moderator maps", "moderator", ix["8,8"] and ix["8,8"].kind)
  eq("an empty position is simply absent", nil, ix["1,1"])
end

do
  --! A reading with nothing to read from is NIL. A core with no boilers
  --! has no coolant figure; that must not look like a dry loop.
  local c = newCore()
  c["5,7"], c["9,7"] = nil, nil
  local snap = core.scanCore(function(x, y) return c[x .. "," .. y] end)
  eq("no boilers -> no coolant reading", nil, snap.water)
  eq("...and no steam reading", nil, snap.steam)
  local level = core.evaluate(snap, core.DEFAULT_LIMITS, 0)
  eq("...which does not scram the reactor", "ok", level)

  c["7,6"], c["7,8"] = nil, nil
  snap = core.scanCore(function(x, y) return c[x .. "," .. y] end)
  eq("no control rods -> no rod-depth reading (not 0, not 100)", nil, snap.rodDepth)

  local none = core.scanCore(function() return nil end)
  eq("an empty console frame has no temperature", nil, none.temp)
  eq("...and evaluates to a SCRAM, not a cold reactor", "scram",
    (core.evaluate(none, core.DEFAULT_LIMITS, 0)))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- a dead or hostile channel never hides a hot one --")
-- ══════════════════════════════════════════════════════════════════
do
  local c = newCore()
  local snap, cols = core.scanCore(function(x, y)
    if x == 3 and y == 3 then error("component vanished") end
    return c[x .. "," .. y]
  end)
  eq("one failing channel is counted", 1, snap.unread)
  eq("the other nine are still read", 9, #cols)
  eq("...and still judged", 500, snap.temp)
  local level, why = core.evaluate(snap, core.DEFAULT_LIMITS, 0)
  eq("an unreadable channel warns", "warn", level)
  test("...and says so", has(why[1], "could not be read"))

  local gone = core.scanCore(function() error("component vanished") end)
  eq("a console that vanishes entirely counts all 225", 225, gone.unread)
  eq("...has no temperature", nil, gone.temp)
  eq("...and SCRAMs", "scram", (core.evaluate(gone, core.DEFAULT_LIMITS, 0)))

  --! Garbage in the numeric fields is dropped, not propagated: a NaN
  --! hull would compare false against every limit and read as "cool".
  local nan = 0 / 0
  local g = core.scanCore(function(x, y)
    if x == 1 and y == 1 then
      return { type = "FUEL", hullTemp = nan, coreTemp = "hot", coreMaxTemp = 0,
               enrichment = nan, fluxQuantity = math.huge }
    end
  end)
  eq("a NaN hull is not a temperature", nil, g.temp)
  eq("a string coreTemp is not a melt reading", nil, g.melt)
  eq("an infinite flux is not a flux", nil, g.flux)
  eq("...so the lone garbage channel SCRAMs by being unreadable-as-cool", "scram",
    (core.evaluate(g, core.DEFAULT_LIMITS, 0)))

  local weird = core.scanCore(function(x, y)
    if x == 0 and y == 0 then return { type = "SOMETHING_NEW", hullTemp = 100 } end
    if x == 1 and y == 0 then return "not a table" end
  end)
  eq("an unknown ColumnType still counts toward temperature", 100, weird.temp)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the new melt rule --")
-- ══════════════════════════════════════════════════════════════════
do
  local lim = core.DEFAULT_LIMITS
  eq("a melt limit ships", true, lim.meltWarn ~= nil and lim.meltScram ~= nil)
  eq("a cool rod is ok", "ok", (core.evaluate({ temp = 300, melt = 40 }, lim, 0)))
  eq("80 percent of melting point warns", "warn",
    (core.evaluate({ temp = 300, melt = lim.meltWarn }, lim, 0)))
  local level, why = core.evaluate({ temp = 300, melt = 95 }, lim, 0)
  eq("95 percent of melting point SCRAMs", "scram", level)
  test("...and names the fuel", has(why[1], "melting point"))
  eq("a hull at the scram limit still SCRAMs", "scram",
    (core.evaluate({ temp = lim.tempScram, melt = 10 }, lim, 0)))
  eq("a typo'd melt limit falls back to the default",
    lim.meltScram, core.mergeLimits({ meltScram = "hot" }).meltScram)
  eq("a custom melt limit applies", "ok",
    (core.evaluate({ temp = 300, melt = 95 }, core.mergeLimits({ meltWarn = 97, meltScram = 99 }), 0)))
end

do
  local snap = core.normalize({ temp = 1, melt = "85", unread = 2 })
  eq("melt normalizes", 85, snap.melt)
  eq("unread normalizes", 2, snap.unread)
  local f = core.frame({ temp = 450, melt = 72.5 }, "ok", 1, 10, "r")
  eq("a frame carries melt", 72.5, f.melt)
  local back = core.decodeWire(table.unpack(core.encodeWire(f), 1, core.WIRE_ARGS))
  test("melt survives the wire", back and math.abs((back.melt or -1) - 72.5) < 0.01)
  eq("...as a number the display can use", "number", type(back and back.melt))
end

-- ══════════════════════════════════════════════════════════════════
-- Fakes for the command, the service and the SCRAM path
-- ══════════════════════════════════════════════════════════════════
local reactor = { core = newCore(), calls = 0, az5 = 0, az5Result = nil, linked = true }
local console = {
  getColumnData = function(x, y)
    reactor.calls = reactor.calls + 1
    return reactor.core[x .. "," .. y]
  end,
  getRBMKPos = function()
    if reactor.linked then
      return { rbmkCenterX = 10, rbmkCenterY = 64, rbmkCenterZ = -20 }
    end
  end,
  pressAZ5 = function() reactor.az5 = reactor.az5 + 1; return reactor.az5Result end,
  setLevel = function() end,
}

local sent = {}
local modem = { broadcast = function(port, ...)
  sent[#sent + 1] = { port = port, args = table.pack(...) }; return true
end }
local redstone
redstone = { out = {}, setOutput = function(side, v) redstone.out[side] = v end }

local CONSOLE = "c0nsole-0000-0000-0000-000000000001"
local COMPONENTS = {
  [CONSOLE] = { type = "rbmk_console", proxy = console },
  ["m0dem-0000-0000-0000-0000000000002"] = { type = "modem", proxy = modem },
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
  proxy = function(addr) return COMPONENTS[addr] and COMPONENTS[addr].proxy or nil end,
  methods = function(addr)
    local names = {}
    for k, v in pairs(COMPONENTS[addr] and COMPONENTS[addr].proxy or {}) do
      if type(v) == "function" then names[#names + 1] = k end
    end
    return names
  end,
}
local clock = 100
package.loaded["computer"] = {
  uptime = function() return clock end, beep = function() return true end,
}
local ticker
package.loaded["kernel.event"] = {
  interval = function(_, cb) ticker = cb; return 1 end,
  cancelTimer = function() return true end,
}
package.loaded["kernel.log"] = {
  info = function() end, warn = function() end, error = function() end, debug = function() end,
}
--! No `profileName` and no `profile`: the SHIPPED default has to be the
--! real driver, or the add-on works only for people who edit the config.
local CFG_SRC = [[
return {
  name = "ntm-test", pollInterval = 1, mapInterval = 1, telemetryPort = 2200,
  grid = { w = 5, h = 5, shape = "square" },
  limits = { tempWarn = 800, tempScram = 1000, waterMin = 10 },
}
]]
package.loaded["kernel.fs"] = {
  exists = function(p) return p == "/etc/rbmk.cfg" end,
  readFile = function(p) return p == "/etc/rbmk.cfg" and CFG_SRC or nil end,
}

local cmd      = require("rbmk-cmd")
local controld = require("rbmk-controld")

-- ══════════════════════════════════════════════════════════════════
print()
print("-- reading through the command layer --")
-- ══════════════════════════════════════════════════════════════════
do
  local cfg = cmd.loadCfg()
  local profile = cmd.activeProfile(cfg)
  eq("the default profile is the real driver", "ntm-console", profile.driver)
  local ncands = #cmd.candidates(profile)
  eq("the console is found by its real type name", 1, ncands)

  local binding = core.bind(profile, cmd.methodsOf(CONSOLE))
  eq("a console with the real surface binds", true, (core.bindingUsable(binding, false)))

  reactor.calls = 0
  local snap, cols = cmd.read(console, binding)
  eq("one read is one scan", 225, reactor.calls)
  eq("readings come back normalized", 500, snap.temp)
  eq("the channels come back with them", 9, #cols)

  local snap2, cols2 = cmd.read({}, binding)
  eq("a proxy without the accessor reads as no temperature", nil, snap2.temp)
  eq("...and no channels", 0, #cols2)
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- SCRAM: a call that moved no rod is not a SCRAM --")
-- ══════════════════════════════════════════════════════════════════
do
  local profile = core.PROFILES["hbm-ntm"]
  local binding = core.bind(profile, { "getColumnData", "pressAZ5" })

  reactor.az5, reactor.az5Result = 0, nil
  local fired, how = cmd.scram(console, binding, {})
  eq("pressAZ5 returning nothing is a fired SCRAM", true, fired)
  eq("...it was pressed once", 1, reactor.az5)
  test("...and the log says how", has(how, "pressAZ5"))

  --! The mod reports "no manual rods in range" as a RETURN VALUE, not an
  --! error. pcall succeeds; a naive check would call this a SCRAM.
  reactor.az5Result = "No control rods found"
  fired, how = cmd.scram(console, binding, {})
  eq("'No control rods found' is NOT a SCRAM", false, fired)
  test("...and the reason is reported", has(how, "No control rods found"))

  COMPONENTS["r3dstone-0000-0000-0000-000000000003"] = { type = "redstone", proxy = redstone }
  redstone.out = {}
  fired, how = cmd.scram(console, binding, { az5RedstoneSide = 2 })
  eq("the redstone AZ-5 line still fires when the rods are missing", true, fired)
  eq("...driving the configured side to 15", 15, redstone.out[2])
  test("...and both paths are in the log",
    has(how, "refused") and has(how, "redstone side 2"))
  COMPONENTS["r3dstone-0000-0000-0000-000000000003"] = nil
  reactor.az5Result = nil
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the survey proves the link, not just the names --")
-- ══════════════════════════════════════════════════════════════════
do
  local lines = {}
  local function out(s) lines[#lines + 1] = tostring(s) end
  reactor.linked = true
  cmd.run({ "survey" }, out)
  local text = table.concat(lines, "\n")
  test("a linked console reports its centre", has(text, "linked, centre 10, 64, -20"))
  test("it counts the channels it scanned", has(text, "9 channels"))
  test("...by kind", text:find("4 fuel", 1, true) and text:find("2 boiler", 1, true))
  test("it reports the hottest hull and rod", has(text, "hull 500 C") and has(text, "70% of melting point"))
  test("it declares the binding usable", has(text, "usable:  YES"))

  lines = {}
  reactor.linked = false
  cmd.run({ "survey" }, out)
  text = table.concat(lines, "\n")
  test("an unlinked console is called out", has(text, "NOT LINKED"))
  reactor.linked = true

  lines = {}
  cmd.run({ "status" }, out)
  text = table.concat(lines, "\n")
  test("status reports the melt margin", has(text, "melt"))
  test("a healthy core reads OK", has(text, "OK"))
end

-- ══════════════════════════════════════════════════════════════════
print()
print("-- the service, end to end --")
-- ══════════════════════════════════════════════════════════════════
do
  reactor.core, reactor.linked, reactor.az5, reactor.az5Result = newCore(), true, 0, nil
  local ok = controld.start()
  eq("the service starts against a real-shaped console", true, ok)
  test("...and armed its interval", ticker ~= nil)

  sent = {}
  reactor.calls = 0
  clock = clock + 1
  ticker()
  eq("one tick is one scan (map and safety share it)", 225, reactor.calls)
  eq("...and one broadcast", 1, #sent)
  eq("the display grid does not shrink the scan (grid was 5x5)", 225, reactor.calls)

  local frame = core.decodeWire(table.unpack(sent[1].args, 1, sent[1].args.n))
  test("the frame decodes", frame ~= nil)
  eq("healthy core: level ok", "ok", frame and frame.level)
  eq("...with the hull temperature", 500, frame and frame.temp)
  test("...the melt margin", frame and frame.melt and math.abs(frame.melt - 70) < 0.1)
  eq("...and no SCRAM was fired", 0, reactor.az5)
  reactor.core = newCore()
  reactor.core["8,6"] = fuel(500, 1000, 2000, 0.6, 120)       -- 50 %
  sent = {}
  clock = clock + 1
  ticker()
  frame = core.decodeWire(table.unpack(sent[1].args, 1, sent[1].args.n))
  eq("a cooled rod is ok", "ok", frame and frame.level)
  eq("...and still no SCRAM", 0, reactor.az5)

  reactor.core["8,6"] = fuel(500, 1900, 2000, 0.6, 120)       -- 95 %
  sent = {}
  clock = clock + 1
  ticker()
  frame = core.decodeWire(table.unpack(sent[1].args, 1, sent[1].args.n))
  eq("a rod at 95 percent of melting point -> scram", "scram", frame and frame.level)
  eq("...pressAZ5 was pressed", 1, reactor.az5)
  test("...and the frame says why", has(frame and frame.why and frame.why[1], "melting point"))
  test("the controller reports itself scrammed", controld.state().scrammed)

  clock = clock + 1
  ticker()
  eq("the latch holds: no second press while scrammed", 1, reactor.az5)

  -- Back to normal: the latch must NOT clear itself.
  reactor.core["8,6"] = fuel(500, 900, 2000, 0.6, 120)
  clock = clock + 1
  ticker()
  test("conditions normal does not release the latch", controld.state().scrammed)
  eq("...and still only one press", 1, reactor.az5)
  controld.stop()
end

do
  -- A console that stops answering mid-run is a SCRAM, not "ok".
  reactor.core, reactor.az5 = newCore(), 0
  controld.start()
  sent = {}
  clock = clock + 1
  ticker()
  eq("armed and healthy", 0, reactor.az5)
  reactor.core = {}                        -- every channel now nil
  sent = {}
  clock = clock + 1
  ticker()
  local frame = core.decodeWire(table.unpack(sent[1].args, 1, sent[1].args.n))
  eq("a console that reports no channels SCRAMs", "scram", frame and frame.level)
  eq("...and pressAZ5 was pressed", 1, reactor.az5)
  controld.stop()
end

do
  -- Unrecoverable at start: refuse rather than idle beside a reactor.
  local saved = console.pressAZ5
  console.pressAZ5 = nil
  local ok = controld.start()
  eq("a console without pressAZ5 is refused at start", false, ok)
  console.pressAZ5 = saved
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
