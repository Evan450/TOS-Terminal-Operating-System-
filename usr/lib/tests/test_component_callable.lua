-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: component methods are CALLABLE TABLES         ║
-- ║                                                                ║
-- ║  On real OpenComputers a component proxy's methods are not      ║
-- ║  functions. machine.lua builds each one as                      ║
-- ║    setmetatable({address = a, name = m}, componentCallback)     ║
-- ║  where componentCallback has __call. type() of one is "table".  ║
-- ║  Every stub in this suite used plain functions, so seven places ║
-- ║  that asked `type(x) == "function"` of a component method       ║
-- ║  passed here and were wrong on every real machine:              ║
-- ║   * compat.term's term.gpu(): the markGlassDirty wrapper around ║
-- ║     mutating GPU calls never ran (found by the boot battery,    ║
-- ║     92-term, 2026-09-25 -- the black-status-bar path);          ║
-- ║   * robot.durability(): "no durability()" on every real robot;  ║
-- ║   * the printer status line: every level read "?";              ║
-- ║   * `component <type>`: listed no methods at all;               ║
-- ║   * the data-card probes in datacard, compress and sysinfo      ║
-- ║     (fallback paths).                                           ║
-- ║  The stubs here are shaped the way machine.lua shapes them.     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_component_callable.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- One method, shaped as OpenComputers shapes it.
local callback = { __call = function(self, ...) return self.fn(...) end }
local function ocMethod(name, fn)
  return setmetatable({ address = "addr", name = name, fn = fn }, callback)
end
local function ocProxy(addr, ctype, methods)
  local p = { address = addr, type = ctype, slot = -1, fields = {} }
  for name, fn in pairs(methods) do p[name] = ocMethod(name, fn) end
  return p
end
test("the stub is shaped like OC's: a method is a callable table",
  type(ocMethod("x", function() end)) == "table")

local function readSrc(path)
  local h = assert(io.open(path, "rb"))
  local s = h:read("*a"); h:close()
  return (s:gsub("\r\n", "\n"))
end

-- ── Shared stubs ────────────────────────────────────────────────
package.loaded["computer"] = {
  uptime = function() return 10 end, pullSignal = function() end,
  pushSignal = function() end, address = function() return "pc" end,
}
local gpuCalls = {}
local gpu = ocProxy("g1", "gpu", {
  getResolution = function() return 80, 25 end,
  setBackground = function(c) gpuCalls[#gpuCalls + 1] = c; return 0 end,
  set = function() return true end,
})
local dataCard = ocProxy("d1", "data", {
  sha256 = function() return "" end, md5 = function() return "" end,
  encrypt = function() return "" end, generateKeyPair = function() end,
  deflate = function(s) return s end, inflate = function(s) return s end,
})
package.loaded["component"] = {
  list = function(t)
    local m = ({ gpu = "g1", data = "d1", screen = "s1" })[t]
    local done = false
    return function() if done or not m then return nil end done = true; return m, t end
  end,
  proxy = function(a) return ({ g1 = gpu, d1 = dataCard })[a] end,
  methods = function() error("no methods here") end,
  type = function(a) return ({ g1 = "gpu", d1 = "data", s1 = "screen" })[a] end,
  isAvailable = function() return true end,
}
local dirty = 0
package.loaded["kernel.display"] = {
  getSize = function() return 80, 25 end,
  set = function() end, fill = function() end, clear = function() end,
  getGpu = function() return gpu end,
  invalidateColors = function() dirty = dirty + 1 end,
}
package.loaded["kernel.screen"] = {
  callerSeat = function() return nil end,
  seatDevices = function() return nil end,
  invalidateAll = function() dirty = dirty + 1 end,
}

-- ── compat.term: term.gpu() / _gpuForCaps ──────────────────────
do
  local term = require("compat.term")
  local rw = term._gpuForCaps({ gpu = true })
  local before = dirty
  local okC, errC = pcall(function() return rw.setBackground(0x0000FF) end)
  test("a display-cap proxy's setBackground reaches the GPU", okC and gpuCalls[#gpuCalls] == 0x0000FF)
  test("...and marks the glass dirty (both caches told)", dirty >= before + 2)
  test("the mutating method comes back WRAPPED, not as the raw callable",
    type(rw.setBackground) == "function")
  local ro = term.gpu()
  local okR, w = pcall(function() return ro.getResolution() end)
  test("a read-only proxy still answers getResolution", okR and w == 80)
  local okD, r1 = pcall(function() return ro.setBackground(1) end)
  test("...and still refuses setBackground without the cap", okD and r1 == false)
  if not okC then print("    (setBackground raised: " .. tostring(errC) .. ")") end
end

-- ── peripheral.robot: durability() ─────────────────────────────
do
  local robotProxy = ocProxy("r1", "robot", { durability = function() return 0.75 end })
  package.loaded["kernel.hal"] = { proxy = function(t) return t == "robot" and robotProxy or nil end }
  package.loaded["kernel.process"] = { current = function() return nil end }
  local robot = require("peripheral.robot")
  local v, why = robot.durability()
  test("robot.durability() reads a real robot's tool (got " .. tostring(v) .. ", " .. tostring(why) .. ")",
    v == 0.75)
end

-- ── kernel.datacard: capsOf with no address (the fallback probe) ─
do
  local dc = require("kernel.datacard")
  local caps = dc.capsOf(dataCard, nil)
  local any = false
  for _, v in pairs(caps) do if v then any = true end end
  test("datacard's fallback probe sees a real card's methods", any and caps.hash == true)
  package.loaded["kernel.datacard"] = nil
end

-- ── kernel.compress: init's own probe, when kernel.datacard is absent ─
do
  package.preload["kernel.datacard"] = function() error("absent for this test") end
  local okC, cmp = pcall(require, "kernel.compress")
  local avail = okC and cmp.init({}) or false
  test("compress's fallback probe sees a real card's deflate", avail == true)
  package.preload["kernel.datacard"] = nil
end

-- ── The printer status line (shell admin), lifted from source ───
do
  local src = readSrc("tos/shell/panels/commands/admin.lua")
  local body = src:match("\n%s*(local function lvl%(fn%).-\n%s*end)\n%s*cinfo =")
  test("found lvl() in admin.lua", body ~= nil)
  if body then
    local lvl = load(body .. "\nreturn lvl", "=lvl", "t",
      { pcall = pcall, tonumber = tonumber, tostring = tostring, math = math, type = type })()
    test("a real paper-level method reads as a number, not \"?\"",
      lvl(ocMethod("getPaperLevel", function() return 42 end)) == "42")
    test("a missing method still reads \"?\"", lvl(nil) == "?")
  end
end

-- ── `component <type>` method listing (shell extras), lifted ─────
do
  local src = readSrc("tos/shell/panels/commands/extras.lua")
  local loop = src:match("local methods = {}\n(.-)\n%s*table%.sort%(methods%)")
  test("found the method-listing loop in extras.lua", loop ~= nil)
  if loop then
    local list = load("return function(proxy)\nlocal methods = {}\n" .. loop
      .. "\ntable.sort(methods)\nreturn methods\nend", "=list", "t",
      { pairs = pairs, type = type, getmetatable = getmetatable, table = table })()
    local m = list(ocProxy("g1", "gpu", { set = function() end, get = function() end }))
    test("a real proxy's methods are listed, and its plain fields are not ("
      .. table.concat(m, ",") .. ")", #m == 2 and m[1] == "get" and m[2] == "set")
  end
end

-- ── sysinfo's data-card tier, fallback path, lifted ─────────────
do
  local src = readSrc("tos/kernel/sysinfo.lua")
  local names = src:match("\n(local DATA_TIER_NAMES = %b{})")
  local fn = src:match("\n(local function dataCardTier%(p, overrides, addr%).-\nend)\n")
  test("found dataCardTier in sysinfo.lua", names ~= nil and fn ~= nil)
  if names and fn then
    local tierOf = load(names .. "\n" .. fn .. "\nreturn dataCardTier", "=tier", "t", {
      pcall = pcall, tonumber = tonumber, type = type,
      require = function() error("kernel.datacard absent") end,
    })()
    local t = tierOf(dataCard, nil, nil)
    test("sysinfo's fallback reads a T3 card as T3 (got " .. tostring(t) .. ")", t == 3)
  end
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
