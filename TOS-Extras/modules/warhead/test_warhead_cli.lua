-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: warhead's command line and screen, end to end         ║
-- ║                                                              ║
-- ║  Loads the REAL init.lua inside a fake of the package        ║
-- ║  sandbox — a GPU that keeps a screen buffer, a keyboard fed  ║
-- ║  from a script, a session-bound fs, and a transposer with a  ║
-- ║  bomb beside it — and drives it the way an operator would.   ║
-- ║  The model is tested in test_warhead.lua; this is the seam   ║
-- ║  where a screen that cannot draw, a settings file that does  ║
-- ║  not round-trip, or a scan that reads the wrong slot would   ║
-- ║  otherwise only show up in a world.                          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/warhead/test_warhead_cli.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local ROOT = "modules/warhead/"

-- ── A screen that remembers what was drawn ────────────────────────────
local function utf8chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

local function makeFixture(opts)
  opts = opts or {}
  local W, H = opts.W or 80, opts.H or 25
  local fx = { files = opts.files or {}, out = {}, rows = {} }
  for y = 1, H do fx.rows[y] = {} for x = 1, W do fx.rows[y][x] = " " end end
  function fx.text() local t = {} for y = 1, H do t[y] = table.concat(fx.rows[y]) end return table.concat(t, "\n") end
  fx.screens = {}

  local gpu = {
    getResolution = function() return W, H end,
    getDepth      = function() return opts.depth or 8 end,
    setForeground = function() end,
    setBackground = function() end,
    set = function(x, y, s)
      if y < 1 or y > H then return end
      for i, ch in ipairs(utf8chars(s)) do
        local xx = x + i - 1
        if xx >= 1 and xx <= W then fx.rows[y][xx] = ch end
      end
    end,
    fill = function(x, y, w, h, ch)
      for yy = y, y + h - 1 do
        for xx = x, x + w - 1 do
          if yy >= 1 and yy <= H and xx >= 1 and xx <= W then fx.rows[yy][xx] = ch end
        end
      end
    end,
  }
  local component = {
    list = function(ctype)
      local done = false
      return function()
        if done or ctype ~= "gpu" then return nil end
        done = true
        return "gpu-addr", "gpu"
      end
    end,
    proxy = function() return gpu end,
  }
  local queue = {}
  for _, s in ipairs(opts.keys or {}) do queue[#queue + 1] = s end
  local computer = {
    uptime = function() return 0 end,
    pullSignal = function()
      -- Every keypress first takes a picture of the screen it answers.
      fx.screens[#fx.screens + 1] = fx.text()
      local s = table.remove(queue, 1)
      if s then return table.unpack(s) end
      return "interrupted"      -- the script ran out: get out, don't hang
    end,
  }
  local fs = {
    home = function() return "/home/tester" end,
    exists = function(p) return fx.files[p] ~= nil end,
    readFile = function(p) return fx.files[p] end,
    writeFile = function(p, d) fx.files[p] = d; return true end,
  }
  local inventory = opts.inventory

  local env
  local loaded = {}
  local function req(name)
    if name == "component" then return component end
    if name == "computer" then return computer end
    -- The shared shortcut table, as a real TOS has it ("^Q / F10"); absent
    -- unless a test asks, as on an older base image.
    if name == "shell.keys" and opts.quitLabel then
      return {
        is = function(action, ch, code) return action == "quit" and (ch == 17 or code == 68) end,
        label = function(action) return action == "quit" and opts.quitLabel or "" end,
      }
    end
    if name == "peripheral.inventory" then
      if inventory then return inventory end
      error("no inventory component")
    end
    if name:sub(1, 8) == "warhead." then
      if loaded[name] then return loaded[name] end
      local chunk = assert(loadfile(ROOT .. name:sub(9) .. ".lua", "t", env))
      loaded[name] = chunk()
      return loaded[name]
    end
    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
  env = setmetatable({ require = req, fs = fs }, { __index = _G })
  local main = assert(loadfile(ROOT .. "init.lua", "t", env))()
  fx.run = function(args)
    fx.out = {}
    main.commands.warhead(args, function(t) fx.out[#fx.out + 1] = tostring(t) end)
    return table.concat(fx.out, "\n")
  end
  fx.W = main.text
  return fx
end

-- Keys, as OpenComputers delivers them: (key_down, kbd, char, code).
local function key(code, ch) return { "key_down", "kbd", ch or 0, code } end
local function char(c) return key(0, c:byte()) end
local function typed(s) local t = {} for c in s:gmatch(".") do t[#t + 1] = char(c) end return t end
local CTRL_Q = key(16, 17)
local ENTER, DOWN, UP = key(28, 13), key(208), key(200)
local function script(...)
  local out = {}
  for _, part in ipairs({ ... }) do
    if part[1] == "key_down" then out[#out + 1] = part
    else for _, k in ipairs(part) do out[#out + 1] = k end end
  end
  return out
end

-- A transposer with bombs on two sides.
local function fakeInventory(sides)
  local NAMES = { [0] = "bottom", "top", "north", "south", "west", "east" }
  return {
    available = function() return true end,
    sides = function()
      local out = {}
      for s, inv in pairs(sides) do out[#out + 1] = { side = s, name = NAMES[s], size = inv.size } end
      table.sort(out, function(a, b) return a.side < b.side end)
      return out
    end,
    stacks = function(side)
      local inv = sides[side]
      if not inv then return nil, "no inventory on that side" end
      local out = {}
      for slot, st in pairs(inv.slots) do
        out[#out + 1] = { slot = slot, id = st[1], damage = st[2] or 0, count = st[3] or 1, label = st[1] }
      end
      return out
    end,
  }
end

print("=== The command line ===")
do
  local fx = makeFixture()
  local out = fx.run({ "list" })
  test("list names the Tsar Bomba", out:find("Tsar Bomba", 1, true) ~= nil)
  test("list gives its radius", out:find("tsar.-r500") ~= nil)
  out = fx.run({ "sim", "tsar" })
  test("sim tsar: radius 500", out:find("radius 500", 1, true) ~= nil)
  test("sim tsar: fallout (int)(500 * 2.5) = 1250", out:find("rain out to 1250", 1, true) ~= nil)
  test("sim tsar: blast to 1000", out:find("hurts to 1000", 1, true) ~= nil)
  out = fx.run({ "sim", "fleija" })
  test("sim fleija: the jammer warning", out:find("Field Disturber", 1, true) ~= nil)
  out = fx.run({ "sim", "nonsense-bomb" })
  test("an unknown name says how to find one", out:find("warhead list", 1, true) ~= nil)
end
do
  local fx = makeFixture()
  local out = fx.run({ "best", "hydro" })
  test("best hydro: 350", out:find("radius 350", 1, true) ~= nil)
  test("best hydro: lists 2 Tritium-Deuterium-Cakes", out:find("2 x Tritium-Deuterium-Cake", 1, true) ~= nil)
  test("best hydro: 8 of 27 slots", out:find("8 of 27 slots", 1, true) ~= nil)
  out = fx.run({ "best" })
  test("best with no kind lists the kinds", out:find("Thermonuclear", 1, true) ~= nil)
end
do
  local fx = makeFixture()
  local out = fx.run({ "config", "set", "boyRadius", "150" })
  test("config set reports", out:find("Set boyRadius = 150", 1, true) ~= nil)
  test("and saves in the caller's home", (fx.files["/home/tester/.warhead"] or ""):find("cfg boyRadius 150", 1, true) ~= nil)
  out = fx.run({ "sim", "boy" })
  test("the override is used: Little Boy at 150", out:find("radius 150", 1, true) ~= nil)
  fx.run({ "config", "reset" })
  out = fx.run({ "sim", "boy" })
  test("reset puts the mod's 120 back", out:find("radius 120", 1, true) ~= nil)
  out = fx.run({ "config", "set", "boyRadius", "huge" })
  test("a non-number is refused", out:find("needs a number", 1, true) ~= nil)
end
do
  local fx = makeFixture()
  local out = fx.run({ "shelter", "boy", "60", "concrete", "1" })
  test("shelter: 1 block of concrete at half Little Boy's radius holds",
    out:find("holds", 1, true) ~= nil and out:find("NOT", 1, true) == nil)
  out = fx.run({ "shelter", "boy", "5", "dirt", "3" })
  test("shelter: 3 dirt at 5 blocks does not", out:find("will NOT hold", 1, true) ~= nil)
  out = fx.run({ "shelter", "boy", "5", "unobtainium" })
  test("an unknown material is named", out:find("Unknown material", 1, true) ~= nil)
end

print()
print("=== Scanning a real bomb through a transposer ===")
do
  -- An Ivy Mike with lenses and core but no deuterium stage (east), and a
  -- custom nuke (south): 2 Explosive Charges, 7 Neptunium, and a stick in
  -- slot 27 that is no ingredient.
  local mike = { size = 8, slots = {} }
  for s = 1, 4 do mike.slots[s] = { "hbm:man_explosive8" } end
  mike.slots[5] = { "hbm:man_core" }
  local custom = { size = 27, slots = {} }
  custom.slots[1] = { "hbm:det_charge", 0, 64 }
  custom.slots[2] = { "hbm:det_charge" }
  for s = 3, 9 do custom.slots[s] = { "hbm:ingot_neptunium" } end
  custom.slots[27] = { "minecraft:stick" }
  local fx = makeFixture({ inventory = fakeInventory({ [5] = mike, [3] = custom }) })
  local out = fx.run({ "scan" })
  test("the Mike is recognised", out:find("east side (8 slots): Ivy Mike", 1, true) ~= nil)
  test("and caught fizzling to 175", out:find("Fizzles to Fat Man's 175", 1, true) ~= nil)
  test("naming the missing deuterium tank", out:find("Deuterium Tank", 1, true) ~= nil)
  test("the custom nuke is read: a 200 fission", out:find("Nuclear blast (MK5), radius 200", 1, true) ~= nil)
  test("the stick is reported as adding nothing", out:find("slot 27 holds minecraft:stick", 1, true) ~= nil)
  out = fx.run({ "scan", "east" })
  test("scan <side> reads one side only", out:find("Ivy Mike", 1, true) ~= nil and out:find("Custom", 1, true) == nil)
end
do
  -- Design from a chest: 1 C-4, 1 Explosive Charge, 5 Pu-239, 6 deuterium cells.
  local chest = { size = 27, slots = {
    [1] = { "hbm:ingot_c4" }, [2] = { "hbm:det_charge" }, [3] = { "hbm:ingot_pu239", 0, 5 },
    [4] = { "hbm:cell", 8, 6 }, [5] = { "hbm:cell", 0, 3 } } }
  local fx = makeFixture({ inventory = fakeInventory({ [4] = chest }) })
  local out = fx.run({ "best", "hydro", "stock", "west" })
  test("best from a chest: 188 with what is there", out:find("radius 188", 1, true) ~= nil)
  test("empty cells are not counted as deuterium", out:find("6 x Deuterium Cell", 1, true) ~= nil)
end
do
  local fx = makeFixture()
  local out = fx.run({ "scan" })
  test("scan with no transposer says so", out:find("no transposer", 1, true) ~= nil)
end

print()
print("=== Settings file ===")
do
  local W = makeFixture().W
  local st = W.newSettings()
  st.cfg.tsarRadius = 400
  st.designs["big one"] = { "det_charge", "det_charge", nil, "td_cake" }
  st.order[1] = "big one"
  st.places[1] = { name = "Base", dx = 120, dz = -40 }
  local back = W.parseSettings(W.serializeSettings(st))
  test("config round-trips", back.cfg.tsarRadius == 400)
  test("a design round-trips, empty slots included",
    back.designs["big one"][1] == "det_charge" and back.designs["big one"][3] == nil
    and back.designs["big one"][4] == "td_cake")
  test("a place round-trips", back.places[1].name == "Base" and back.places[1].dz == -40)
  local hostile = W.parseSettings("WARHEAD1\ncfg print 1\ndesign x\tos.execute,td_cake\nplace 1 2 ok")
  test("unknown config keys and item keys are dropped",
    hostile.cfg.print == nil and hostile.designs.x[1] == nil and hostile.designs.x[2] == "td_cake")
  test("names lose control characters", W.cleanName("a\tb\nc") == "a b c")
end

print()
print("=== The screen ===")
do
  local fx = makeFixture({ W = 50, H = 16 })
  local out = fx.run({})
  test("a 50x16 screen is told the size it needs, and pointed at the commands",
    out:find("80x24", 1, true) ~= nil and out:find("warhead help", 1, true) ~= nil)
end
do
  -- Down to Little Boy, look at the map, back, then open the designer,
  -- ask for the best thermonuclear, decline salting, save it as "big",
  -- and quit.
  local keys = script(
    { DOWN, DOWN },                       -- Custom -> Gadget -> Little Boy
    { char("m") },                        -- the map
    { CTRL_Q },                           -- back to the list
    { char("s") }, { DOWN }, { CTRL_Q },  -- the shelter, one block nearer, back
    { UP, UP, ENTER },                    -- the designer
    { char("b") }, typed("thermo"), { ENTER },   -- best: thermonuclear
    { char("n") },                        -- no salting
    { char("g") }, typed("big"), { ENTER },      -- save as "big"
    { CTRL_Q }, { CTRL_Q })
  local fx = makeFixture({ keys = keys })
  local ok, err = pcall(fx.run, {})
  test("a whole session runs without an error" .. (ok and "" or (" (" .. tostring(err) .. ")")), ok)
  local S = fx.screens
  local function any(pat)
    for _, s in ipairs(S) do if s:find(pat, 1, true) then return true end end
    return false
  end
  test("the list shows Little Boy's report", any("Nuclear blast (MK5), radius 120"))
  test("the map draws its legend", any("one tick kills"))
  test("the map names its scale", any("1 column = "))
  test("the shelter planner shows the distance", any("Distance  49"))
  test("the designer shows the stage table", any("Stages"))
  test("best thermonuclear lands in the grid", any("Tritium-Deut"))
  test("and the outcome reads 350", any("Nuclear blast (MK5) r350"))
  test("the list keeps its label column when it wraps", any("Blocks    carved"))
  local saved = fx.files["/home/tester/.warhead"] or ""
  test("the design is saved under its name", saved:find("design big\t", 1, true) ~= nil)
  test("with the cake in it", saved:find("td_cake", 1, true) ~= nil)
end
do
  -- A one-bit screen draws the map in ASCII.
  local keys = script({ DOWN, DOWN }, { char("m") }, { CTRL_Q }, { CTRL_Q })
  local fx = makeFixture({ keys = keys, depth = 1 })
  local ok = pcall(fx.run, {})
  local found = false
  for _, s in ipairs(fx.screens) do if s:find("#", 1, true) and s:find("%", 1, true) then found = true end end
  test("monochrome: the rings are drawn in ASCII", ok and found)
end

do
  -- On a real TOS the quit label is "^Q / F10". The list's key bar was
  -- built for "^Q" and the headless machine showed it cut to "Qu".
  local fx = makeFixture({ keys = { CTRL_Q }, quitLabel = "^Q / F10" })
  pcall(fx.run, {})
  local bottom = (fx.screens[1] or ""):match("([^\n]*)$") or ""
  test("the key bar ends on the whole way out: " .. bottom:gsub("%s+$", ""),
    bottom:gsub("%s+$", ""):sub(-13) == "^Q / F10 Quit")
  local W = fx.W
  test("fitKeys drops whole hints from the right, never the way out",
    W.fitKeys({ "aaaa", "bbbb", "cccc" }, "QUIT", 18) == "aaaa \194\183 bbbb \194\183 QUIT")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All tests passed.")
