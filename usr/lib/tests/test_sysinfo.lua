-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: sysinfo (System Configuration)      ║
-- ║  - tier heuristics (mem/gpu/disk)                      ║
-- ║  - gather() builds the inventory from mocked hardware  ║
-- ║  - data-card tier inferred from method set             ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sysinfo.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_sysinfo.lua"
local base = here:gsub("[^/\\]*$", "")
local sysinfo
for _, p in ipairs({ base .. "../../../tos/kernel/sysinfo.lua",
    "tos/kernel/sysinfo.lua", "TOS-Dev/tos/kernel/sysinfo.lua" }) do
  local chunk = loadfile(p)
  if chunk then sysinfo = chunk(); break end
end
if not sysinfo then
  print("FAIL: could not load sysinfo.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== sysinfo Tests ===")
print()

-- ── Tier heuristics (exported for testing) ─────────────────────────
test("memTier 512 -> T2+",  "T2+",  sysinfo._memTier(512))
test("memTier 256 -> T1.5", "T1.5", sysinfo._memTier(256))
test("memTier 128 -> T1",   "T1",   sysinfo._memTier(128))
test("gpuTier depth1 -> 1", 1, sysinfo._gpuTier(1))
test("gpuTier depth4 -> 2", 2, sysinfo._gpuTier(4))
test("gpuTier depth8 -> 3", 3, sysinfo._gpuTier(8))
test("diskTier 512 -> Floppy", "Floppy", sysinfo._diskTier(512))
test("diskTier 1024 -> T1",    "T1",     sysinfo._diskTier(1024))
test("diskTier 2048 -> T2",    "T2",     sysinfo._diskTier(2048))
test("diskTier 4096 -> T3",    "T3",     sysinfo._diskTier(4096))
test("screenTier 160x50 -> 3", 3, sysinfo._screenTier(160, 50))
test("screenTier 80x25 -> 2",  2, sysinfo._screenTier(80, 25))
test("screenTier 50x16 -> 1",  1, sysinfo._screenTier(50, 16))

-- ── Mock hardware ──────────────────────────────────────────────────
local function fn() return function() end end
local comps = {
  { addr = "gpu1aaaaaaaa", type = "gpu",
    proxy = { getDepth = function() return 8 end,
              maxResolution = function() return 160, 50 end } },
  { addr = "scr1aaaaaaaa", type = "screen", proxy = {} },
  { addr = "hdd1aaaaaaaa", type = "filesystem",
    proxy = { spaceTotal = function() return 4096 * 1024 end,
              spaceUsed  = function() return 1000 * 1024 end,
              getLabel   = function() return "boot" end,
              isReadOnly = function() return false end } },
  { addr = "flp1aaaaaaaa", type = "filesystem",
    proxy = { spaceTotal = function() return 512 * 1024 end,
              spaceUsed  = function() return 10 * 1024 end,
              getLabel   = function() return "" end,
              isReadOnly = function() return false end } },
  { addr = "mdm1aaaaaaaa", type = "modem",
    proxy = { isWireless = function() return true end,
              getStrength = function() return 400 end } },
  { addr = "dat1aaaaaaaa", type = "data",
    -- T2 card: has sha256 + encrypt, but no ECC.
    proxy = { sha256 = fn(), encrypt = fn(), md5 = fn() } },
  { addr = "eep1aaaaaaaa", type = "eeprom",
    proxy = { getLabel = function() return "TOS BIOS" end,
              getSize = function() return 4096 end } },
  { addr = "rs01aaaaaaaa", type = "redstone", proxy = {} },
}

local mockComponent = {
  list = function(filter)
    local i = 0
    return function()
      while true do
        i = i + 1
        local e = comps[i]
        if not e then return nil end
        if filter == nil or e.type == filter then return e.addr, e.type end
      end
    end
  end,
  proxy = function(addr)
    for _, e in ipairs(comps) do if e.addr == addr then return e.proxy end end
  end,
  type = function(addr)
    for _, e in ipairs(comps) do if e.addr == addr then return e.type end end
  end,
}
local mockComputer = {
  totalMemory = function() return 524288 end,   -- 512 KB
  freeMemory  = function() return 262144 end,    -- 256 KB
  getArchitecture = function() return "Lua 5.3" end,
  getBootAddress  = function() return "hdd1aaaaaaaa" end,
}

local inv = sysinfo.gather({ component = mockComponent, computer = mockComputer })

print("")
-- ── Inventory assertions ───────────────────────────────────────────
test("cpu arch", "Lua 5.3", inv.cpu.arch)
test("memory totalKB", 512, inv.memory.totalKB)
test("memory tier", "T2+", inv.memory.tier)
test("gpu count", 1, inv.gpu.count)
test("gpu tier (depth 8)", 3, inv.gpu.tier)
test("gpu maxW", 160, inv.gpu.maxW)
test("screen count", 1, inv.screen.count)
test("screen tier", 3, inv.screen.tier)
test("disk count", 2, #inv.disks)
test("disks sorted: biggest first label", "boot", inv.disks[1].label)
test("biggest disk tier", "T3", inv.disks[1].tier)
test("floppy tier", "Floppy", inv.disks[2].tier)
test("modem count", 1, #inv.modems)
test("modem wireless", true, inv.modems[1].wireless)
test("modem strength", 400, inv.modems[1].strength)
test("data card present", true, inv.dataCard.present)
test("data card tier inferred T2", 2, inv.dataCard.tier)
test("data card tier source = detected", "detected", inv.dataCard.tierSource)
test("eeprom label", "TOS BIOS", inv.eeprom.label)
test("eeprom bootAddr (8 chars)", "hdd1aaaa", inv.eeprom.bootAddr)
test("other peripherals: redstone present", true,
  (function() for _, o in ipairs(inv.other) do if o.type == "redstone" then return true end end return false end)())

-- ── CPU tier: detect / override / estimate / unknown ───────────────
-- No deviceInfo + no override, but RAM is known => estimate (512K -> T2).
test("cpu tier estimated from RAM", "estimated", inv.cpu.tierSource)
test("cpu tier estimate value (512K -> T2)", 2, inv.cpu.tier)
-- Truly unknown only when even RAM is unavailable.
do
  local noRam = { freeMemory = function() return 0 end, totalMemory = function() return 0 end,
    getArchitecture = function() return "Lua 5.3" end }
  local invU = sysinfo.gather({ component = mockComponent, computer = noRam })
  test("cpu tier unknown when no RAM figure", "unknown", invU.cpu.tierSource)
  test("cpu tier nil when unknown", nil, invU.cpu.tier)
end
-- Operator override corrects it.
local invO = sysinfo.gather({ component = mockComponent, computer = mockComputer }, { cpuTier = 2 })
test("cpu tier override applied", 2, invO.cpu.tier)
test("cpu tier source = override", "override", invO.cpu.tierSource)

-- ── Data Card tier: detect / override / unknown ────────────────────
-- Override pins the tier regardless of detected methods (the in-game
-- "present (unknown tier)" recovery path).
local invDC = sysinfo.gather({ component = mockComponent, computer = mockComputer }, { dataTier = 3 })
test("data tier override applied", 3, invDC.dataCard.tier)
test("data tier source = override", "override", invDC.dataCard.tierSource)
test("data tier override names T3", true,
  (invDC.dataCard.name or ""):find("T3", 1, true) ~= nil)
-- A card whose methods don't probe cleanly classifies as unknown (tier 0).
do
  local comps2 = {}
  for _, e in ipairs(comps) do
    if e.type == "data" then comps2[#comps2 + 1] = { addr = e.addr, type = "data", proxy = {} }
    else comps2[#comps2 + 1] = e end
  end
  local mc2 = {
    list = function(filter)
      local i = 0
      return function()
        while true do
          i = i + 1; local e = comps2[i]
          if not e then return nil end
          if filter == nil or e.type == filter then return e.addr, e.type end
        end
      end
    end,
    proxy = function(addr) for _, e in ipairs(comps2) do if e.addr == addr then return e.proxy end end end,
    type = function(addr) for _, e in ipairs(comps2) do if e.addr == addr then return e.type end end end,
  }
  local invU = sysinfo.gather({ component = mc2, computer = mockComputer })
  test("featureless data card -> present", true, invU.dataCard.present)
  test("featureless data card -> tier 0", 0, invU.dataCard.tier)
  test("featureless data card -> source unknown", "unknown", invU.dataCard.tierSource)
  -- ...and the override rescues exactly that case.
  local invUO = sysinfo.gather({ component = mc2, computer = mockComputer }, { dataTier = 3 })
  test("override rescues unknown card", 3, invUO.dataCard.tier)
  -- The render flags an unknown card and stars an overridden one.
  local function findRow(rows, label)
    for _, r in ipairs(rows) do if r.label == label then return r end end
  end
  test("unknown card row warns to set it", true,
    (findRow(sysinfo.rows(invU), "Crypto").value or ""):find("set in boot settings", 1, true) ~= nil)
  test("override card row is starred", true,
    (findRow(sysinfo.rows(invUO), "Crypto").value or ""):find("*", 1, true) ~= nil)
end
-- getDeviceInfo naming the tier => detected.
local di = { ["cpu-addr"] = { class = "processor", description = "CPU (Tier 3)", clock = "1280" } }
local invD = sysinfo.gather({ component = mockComponent, computer = mockComputer, deviceInfo = di })
test("cpu tier detected from deviceInfo", 3, invD.cpu.tier)
test("cpu tier source = detected", "detected", invD.cpu.tierSource)

-- ── progress hook (the "Standby..." flavor) fires ──────────────────
local phases = {}
sysinfo.gather({ component = mockComponent, computer = mockComputer }, nil,
  function(msg) phases[#phases + 1] = msg end)
test("onProgress fired at least once", true, #phases >= 1)

-- ── behavioral CPU benchmark (opt-in) ──────────────────────────────
do
  local calls = 0
  local benchClock = { uptime = function() calls = calls + 1; return calls < 50 and 0 or 1 end }
  local n, tier = sysinfo.benchmarkCallBudget(benchClock)
  test("benchmark counts calls until tick advances", true, n >= 48 and n <= 50)
  test("benchmark returns a coarse tier", true, tier == 1 or tier == 2 or tier == 3)
end

-- ── rows(): sectioned layout ───────────────────────────────────────
local rows = sysinfo.rows(inv)
local function findRow(label)
  for _, r in ipairs(rows) do if r.label == label then return r end end
end
local function hasSection(name)
  for _, r in ipairs(rows) do if r.role == "section" and r.value == name then return true end end
  return false
end
test("rows: System section present",      true, hasSection("System"))
test("rows: Storage section present",     true, hasSection("Storage"))
test("rows: Peripherals section present", true, hasSection("Peripherals"))
test("rows: Processor value names arch", true,
  (findRow("Processor") and findRow("Processor").value:find("Lua 5.3", 1, true)) ~= nil)
test("rows: Processor flagged warn when tier is an estimate", "warn",
  findRow("Processor") and findRow("Processor").role)
test("rows Crypto is ok (data card present)", "ok", findRow("Crypto") and findRow("Crypto").role)
test("rows has a Graphics row", true, findRow("Graphics") ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
