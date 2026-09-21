-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the tape drive has NO getter for speed/volume   ║
-- ║                                                                    ║
-- ║  Found by checking every component call TOS makes against the     ║
-- ║  mod that declares it. Computronics' TileTapeDrive.java exposes    ║
-- ║  exactly this to Lua:                                              ║
-- ║    getLabel getPosition getSize getState isEnd isReady play read   ║
-- ║    seek setLabel setSpeed setVolume stop write                     ║
-- ║  setSpeed and setVolume are there. getSpeed and getVolume are NOT, ║
-- ║  at any tier, in any version of that file.                         ║
-- ║                                                                    ║
-- ║  `tape state`, `tape speed` and `tape volume` all called           ║
-- ║  drive.getSpeed() / drive.getVolume() inside a pcall, so the call  ║
-- ║  failed on EVERY machine: state printed no Speed or Volume line    ║
-- ║  at all, and the bare commands answered "Current speed: ?"         ║
-- ║  forever. The pcall is what made a typo look like a hardware quirk.║
-- ║                                                                    ║
-- ║  The fake drive below therefore has NO getSpeed/getVolume, which   ║
-- ║  is the real hardware's shape. The source lint at the bottom is    ║
-- ║  the durable half: it fails if either name comes back.              ║
-- ║                                                                    ║
-- ║  Checked against the pre-fix file: 14 of these 22 assertions fail  ║
-- ║  on it, the lint among them.                                       ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Run: lua modules/tape/test_tape_speed_volume.lua  (from TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "modules/tape/test_tape_speed_volume.lua"
local base = here:gsub("[^/\\]*$", "")

-- ── A tape drive shaped like the real one: setters, no getters ──────
local setCalls = {}
local function fakeDrive(addr)
  local d = { address = addr }
  d.isReady     = function() return true end
  d.getState    = function() return "STOPPED" end
  d.getPosition = function() return 1024 end
  d.getSize     = function() return 4096 end
  d.getLabel    = function() return "tape" end
  d.setSpeed    = function(v) setCalls[#setCalls + 1] = { "speed", v }; return true end
  d.setVolume   = function(v) setCalls[#setCalls + 1] = { "volume", v }; return true end
  -- deliberately absent: getSpeed, getVolume
  return d
end

local driveA, driveB = fakeDrive("tape-addr-A"), fakeDrive("tape-addr-B")
local current = driveA
local componentStub = {
  list = function(t)
    local done = false
    return function()
      if done or t ~= "tape_drive" then return nil end
      done = true; return current.address, "tape_drive"
    end
  end,
  proxy = function() return current end,
}
local computerStub = { pullSignal = function() end,
                       freeMemory = function() return 0 end,
                       uptime = function() return 0 end }
local function stubRequire(name)
  if name == "component" then return componentStub end
  if name == "computer"  then return computerStub  end
  error("require blocked in sandbox: " .. tostring(name), 0)
end

local src, srcPath
for _, p in ipairs({ base .. "init.lua", "modules/tape/init.lua",
                     "TOS-Extras/modules/tape/init.lua" }) do
  local f = io.open(p, "rb")
  if f then src = f:read("a"); srcPath = p; f:close(); break end
end
if not src then
  print("FAIL: could not read tape/init.lua"); print("*** TESTS FAILED ***")
  return false
end

local fsStub = { exists = function() return false end }
local env = setmetatable({ require = stubRequire, fs = fsStub },
                         { __index = _G })
local chunk = load(src, "=tape/init.lua", "t", env)
if not chunk then
  print("FAIL: tape/init.lua does not parse"); print("*** TESTS FAILED ***")
  return false
end
local mod = chunk()
local tape = mod.commands and mod.commands.tape
if not tape then
  print("FAIL: no tape command"); print("*** TESTS FAILED ***")
  return false
end

local out = {}
local function o(s) out[#out + 1] = tostring(s) end
local function run(...)
  out = {}
  tape({ ... }, o)
end
local function said(needle)
  for _, line in ipairs(out) do
    if line:find(needle, 1, true) then return true end
  end
  return false
end

print("── nothing set yet: say so, do not guess ──")
run("state")
test("state still reports the drive state", said("STOPPED"))
test("state says the speed is not reported", said("Speed:    not reported"))
test("state says the volume is not reported", said("Volume:   not reported"))
run("speed")
test("bare `speed` says the drive does not report it",
     said("does not report its speed"))
run("volume")
test("bare `volume` says the drive does not report it",
     said("does not report its volume"))
test("and none of that raised", true)

print("── after setting, report what WE set, labelled ──")
setCalls = {}
run("speed", "1.5")
test("setSpeed reached the drive with 1.5",
     setCalls[1] and setCalls[1][1] == "speed" and setCalls[1][2] == 1.5)
test("it confirms", said("Speed set to 1.50x"))
run("speed")
test("bare `speed` now recalls it", said("Speed set here: 1.50x"))
run("state")
test("state shows it, marked as set here", said("Speed:    1.50x (set here)"))
test("volume is still unknown", said("Volume:   not reported"))

run("volume", "0.4")
test("setVolume reached the drive", setCalls[2] and setCalls[2][1] == "volume")
run("volume")
test("bare `volume` recalls it", said("Volume set here: 0.40"))
run("state")
test("state shows both", said("Speed:    1.50x (set here)")
     and said("Volume:   0.40 (set here)"))

print("── the memory is per drive, not per machine ──")
current = driveB
run("state")
test("a different drive does not inherit drive A's speed",
     said("Speed:    not reported"))
run("speed", "0.5")
current = driveA
run("state")
test("and drive A keeps its own", said("Speed:    1.50x (set here)"))
current = driveB
run("state")
test("while drive B keeps its own", said("Speed:    0.50x (set here)"))

print("── a refused value is not remembered ──")
current = fakeDrive("tape-addr-C")
setCalls = {}
run("speed", "3")
test("speed 3 is refused (Computronics allows 0.25..2)", said("must be 0.25"))
test("nothing reached the drive", #setCalls == 0)
run("state")
test("and nothing was remembered", said("Speed:    not reported"))
run("volume", "2")
test("volume 2 is refused", said("must be 0..1"))

print("── the source lint: the dead getters must not come back ──")
do
  local realSrc = io.open(srcPath, "rb")
  local text = realSrc and realSrc:read("a") or ""
  if realSrc then realSrc:close() end
  -- Mentions inside the #BUG comment block are fine; a CALL is not.
  local calls = {}
  for line in text:gmatch("[^\n]+") do
    if not line:match("^%s*%-%-") then
      if line:find("getSpeed%s*%(") or line:find("%.getSpeed") then
        calls[#calls + 1] = "getSpeed"
      end
      if line:find("getVolume%s*%(") or line:find("%.getVolume") then
        calls[#calls + 1] = "getVolume"
      end
    end
  end
  test("no code line calls getSpeed or getVolume on the drive", #calls == 0)
  if #calls > 0 then print("    found: " .. table.concat(calls, ", ")) end
end

print("")
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
