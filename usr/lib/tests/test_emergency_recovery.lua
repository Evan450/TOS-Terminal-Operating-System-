-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the emergency shell has a recovery set        ║
-- ║                                                                ║
-- ║  When the main shell cannot load, the root-authenticated        ║
-- ║  emergency shell was the whole toolbox: ls, cat, mem, verify,   ║
-- ║  reboot, shutdown. It now has df, log and srm -- each built to  ║
-- ║  survive the thing that may have broken: df asks the disks      ║
-- ║  through raw component invokes, log falls back from the         ║
-- ║  kernel's ring to the file, srm says so when it will not load.  ║
-- ║                                                                ║
-- ║  kernel.emergencyShell is LIFTED from tos/kernel/init.lua and   ║
-- ║  typed into through a scripted pullSignal.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_emergency_recovery.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local src = assert(io.open("tos/kernel/init.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local body = src:match("(function kernel%.emergencyShell%(%).-\nend)\n")
test("found kernel.emergencyShell", body ~= nil)
if not body then print("*** TESTS FAILED ***"); os.exit(1) end

-- ── A machine whose main shell would not load ──────────────────────
local shown = {}
local display = {
  getSize = function() return 80, 25 end,
  getTheme = function()
    return setmetatable({}, { __index = function(_, k) return k end })
  end,
  clear = function() end, fill = function() end,
  set = function(_, _, text) shown[#shown + 1] = tostring(text) end,
  c = function(k) return k end,
}
local typed = {}
local function type_(line)
  for i = 1, #line do typed[#typed + 1] = { "key_down", "kb", line:byte(i), 0 } end
  typed[#typed + 1] = { "key_down", "kb", 13, 28 }
end
local BOOT, FLOP, DEAD = "b00tdisk-0000", "f10ppy00-0000", "dead0000-0000"
local disks = {
  [BOOT] = { spaceTotal = 4 * 1024 * 1024, spaceUsed = 1024 * 1024, getLabel = "tos", isReadOnly = false },
  [FLOP] = { spaceTotal = 512 * 1024, spaceUsed = 0, getLabel = "data", isReadOnly = true },
  [DEAD] = "raises",
}
local component = {
  list = function(kind)
    local keys = kind == "filesystem" and { BOOT, FLOP, DEAD } or {}
    local i = 0
    return function() i = i + 1; return keys[i] end
  end,
  invoke = function(addr, m)
    local d = disks[addr]
    if d == "raises" then error("disk removed") end
    return d[m]
  end,
}
local computer = {
  pullSignal = function()
    local s = table.remove(typed, 1)
    if not s then error("the shell asked for input the test did not type") end
    return table.unpack(s)
  end,
  freeMemory = function() return 64 * 1024 end, totalMemory = function() return 256 * 1024 end,
  getBootAddress = function() return BOOT end,
}
local files = { ["/var/log/kernel.log"] = "[  1.0][boot] line one\n[  2.0][boot] line two\n" }
local fs = { list = function() return {} end, readFile = function(p) return files[p] end }
local ringBroken = false
local log = {
  recent = function(n)
    if ringBroken then error("log ring gone") end
    return { { time = 3.5, source = "kernel", msg = "the shell would not load" } }
  end,
}
local srmLoads = true
local srmFake = {
  status = function() return { findings = { { text = "POST: no parked fault from SRM Basic", sev = "ok" } } } end,
  scan = function() return { findings = { { text = "2 files drifted from the baseline", sev = "warn" } } } end,
  repair = function(_, opts)
    return { findings = { { text = "fixer pass ran" .. (opts.restore and ", restoring" or ""), sev = "info" } } }
  end,
}
local stopped
local kernel = {
  verifySystem = function(p) p("verified") end,
  reboot = function() stopped = "reboot" end,
  shutdown = function() stopped = "shutdown" end,
}
local env = setmetatable({
  kernel = kernel, display = display, computer = computer, component = component,
  fs = fs, log = log,
  _G = { _TOS = { users = { login = function(_, pw) return pw == "rootpw" and "tok" or nil end,
                            kernelSession = function() return { user = "root", tier = 3 } end } } },
  require = function(n)
    if n == "kernel.srm" then
      if not srmLoads then error("module 'kernel.srm' not found") end
      return srmFake
    end
    return require(n)
  end,
}, { __index = _G })
assert(load(body, "=emergencyShell", "t", env))()

local function session(...)
  shown, typed, stopped = {}, {}, nil
  type_("rootpw")
  for _, cmd in ipairs({ ... }) do type_(cmd) end
  type_("shutdown")
  local ok, err = pcall(kernel.emergencyShell)
  return ok, err
end
local function saw(needle)
  for _, t in ipairs(shown) do if t:find(needle, 1, true) then return true end end
  return false
end

print("=== the emergency shell has a recovery set ===")
print()

local ok, err = session("help")
test("the shell runs and shuts down on request", ok and stopped == "shutdown", err)
test("help lists df, log and srm", saw("df          - Disks") and saw("log [N]") and saw("srm [status|scan|repair"))

session("df")
test("df lists each disk with its space", saw(BOOT:sub(1, 8)) and saw("1024K used of    4096K"))
test("...marks the boot disk and a read-only one", saw("(boot)") and saw("read-only"))
test("...and survives a disk that errors", saw(DEAD:sub(1, 8)) and saw("? used of        ?"))

session("log 5")
test("log prints the kernel's ring", saw("the shell would not load"))
ringBroken = true
session("log")
test("with the ring gone, log reads the file on disk", saw("line two"))
files["/var/log/kernel.log"] = nil
session("log")
test("with neither, it says so", saw("No log available"))
ringBroken = false

session("srm")
test("srm with no argument is srm status", saw("POST: no parked fault"))
session("srm scan")
test("srm scan reports", saw("drifted from the baseline"))
session("srm repair --restore")
test("srm repair passes --restore through", saw("fixer pass ran, restoring"))
session("srm frobnicate")
test("an unknown srm subcommand prints its usage", saw("Usage: srm [status | scan | repair"))
srmLoads = false
ok = session("srm")
test("when srm will not load it says so, and the shell keeps going", ok and stopped == "shutdown"
  and saw("srm will not load"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
