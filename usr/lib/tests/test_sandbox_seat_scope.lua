-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a sandboxed program sees ITS OWN SEAT's    ║
-- ║  display hardware, not the machine's first GPU               ║
-- ║                                                              ║
-- ║  Every TUI package opens its screen the obvious way:         ║
-- ║      local gpuAddr = component.list("gpu")()                 ║
-- ║  which is the FIRST GPU on the bus — seat 1's. On the        ║
-- ║  operator's two-seat rig, `ttt 2p` typed on one seat painted ║
-- ║  its board onto the OTHER seat's screen, over that person's  ║
-- ║  work (emulator round 7). It is also a spoofing surface: an  ║
-- ║  add-on could draw a convincing login prompt on somebody     ║
-- ║  else's display.                                             ║
-- ║                                                              ║
-- ║  The sandbox already routes INPUT per seat (safePullSignal   ║
-- ║  yields for the scheduler's seat-routed delivery). This is   ║
-- ║  the output half: list/proxy/invoke/getPrimary narrow gpu,   ║
-- ║  screen and keyboard to the caller's seat. Crucially it must ║
-- ║  narrow NOTHING when the seat is unresolvable (kernel        ║
-- ║  context, boot, off-box) — a single-seat machine has to      ║
-- ║  behave exactly as it always did.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_seat_scope.lua  (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- ── A two-seat machine ────────────────────────────────────────────
-- Seat 1: gpu-1 / screen-1 / kb-1     Seat 2: gpu-2 / screen-2 / kb-2
local COMPONENTS = {
  ["gpu-1"] = "gpu",       ["gpu-2"] = "gpu",
  ["screen-1"] = "screen", ["screen-2"] = "screen",
  ["kb-1"] = "keyboard",   ["kb-2"] = "keyboard",
  ["geo-1"] = "geolyzer",
}
local ORDER = { "gpu-1", "gpu-2", "screen-1", "screen-2", "kb-1", "kb-2", "geo-1" }

package.loaded["component"] = {
  list = function(filter, exact)
    local i = 0
    return function()
      while true do
        i = i + 1
        local addr = ORDER[i]
        if not addr then return nil end
        local ctype = COMPONENTS[addr]
        local hit = (filter == nil)
          or (exact and ctype == filter)
          or (not exact and ctype:find(filter, 1, true) ~= nil)
        if hit then return addr, ctype end
      end
    end
  end,
  type    = function(addr) return COMPONENTS[addr] end,
  proxy   = function(addr) return { address = addr, _proxy = true } end,
  slot    = function() return 0 end,
  get     = function(addr) return addr end,
  invoke  = function(addr, method) return "invoked:" .. addr .. ":" .. method end,
  isAvailable = function() return true end,
  getPrimary  = function(ctype)
    -- The stock OC answer: the first device of that type on the bus.
    for _, a in ipairs(ORDER) do
      if COMPONENTS[a] == ctype then return { address = a, _proxy = true } end
    end
  end,
}
package.loaded["computer"] = {
  uptime = function() return 0 end,
  freeMemory = function() return 1e6 end, totalMemory = function() return 1e6 end,
  address = function() return "test" end,
  pushSignal = function() end, pullSignal = function() return nil end,
}
package.loaded["kernel.fs"] = {
  exists = function() return false end,
  isDirectory = function() return false end,
  readFile = function() return nil end,
}

-- kernel.screen stands in for the real seat table; kernel.process decides
-- which seat the "calling process" belongs to. Both are what the sandbox
-- consults, so driving them here drives the real code path.
local SEATS = {
  [1] = { gpu = "gpu-1", screen = "screen-1", keyboards = { "kb-1" } },
  [2] = { gpu = "gpu-2", screen = "screen-2", keyboards = { "kb-2" } },
}
local currentSeat = nil          -- nil = unresolvable (kernel/boot/off-box)
package.loaded["kernel.screen"] = {
  seatDevices   = function(idx) return SEATS[idx] end,
  callerSeat    = function() return currentSeat end,
  callerDevices = function() return currentSeat and SEATS[currentSeat] or nil end,
}
package.loaded["kernel.process"] = {
  current = function() return { display = currentSeat } end,
}

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
local sandbox = require("kernel.sandbox")

print("=== sandboxed programs are scoped to their own seat ===")
print()

local function envFor()
  return sandbox.build({ caps = { component = true } })
end
local function listAll(comp, filter)
  local out = {}
  for addr in comp.list(filter) do out[#out + 1] = addr end
  table.sort(out)
  return out
end
local function joined(t) return table.concat(t, ",") end

-- ── Seat 2's program sees only seat 2's hardware ──────────────────
do
  currentSeat = 2
  local env = envFor()
  test("the sandbox exposes a component table", type(env.component) == "table")
  local comp = env.component

  eq("component.list('gpu') is seat 2's GPU alone",
    "gpu-2", joined(listAll(comp, "gpu")))
  eq("component.list('screen') is seat 2's screen alone",
    "screen-2", joined(listAll(comp, "screen")))
  eq("component.list('keyboard') is seat 2's keyboard alone",
    "kb-2", joined(listAll(comp, "keyboard")))

  -- THE BUG: the first thing every game does.
  local first = comp.list("gpu")()
  eq("the FIRST gpu a seat-2 program sees is its own", "gpu-2", first)

  -- Naming the other seat's device explicitly is refused too — otherwise
  -- the narrowing would be a hint rather than a boundary.
  local p, why = comp.proxy("gpu-1")
  test("proxying the other seat's GPU is refused", p == nil)
  test("...with a reason that names the seat (" .. tostring(why) .. ")",
    type(why) == "string" and why:find("seat", 1, true) ~= nil)
  test("proxying its OWN GPU still works",
    (comp.proxy("gpu-2") or {}).address == "gpu-2")

  local okInv = pcall(comp.invoke, "gpu-1", "set")
  test("invoking on the other seat's GPU is refused", okInv == false)
  test("invoking on its own GPU is allowed", (pcall(comp.invoke, "gpu-2", "set")))

  eq("getPrimary('gpu') is the SEAT's primary, not the bus's first",
    "gpu-2", (comp.getPrimary("gpu") or {}).address)
end

-- ── Seat 1 gets seat 1's, symmetrically ───────────────────────────
do
  currentSeat = 1
  local comp = envFor().component
  eq("a seat-1 program sees gpu-1", "gpu-1", joined(listAll(comp, "gpu")))
  test("...and cannot proxy gpu-2", comp.proxy("gpu-2") == nil)
end

-- ── Non-display components are NOT seat-scoped ────────────────────
-- Only gpu/screen/keyboard belong to a seat; narrowing anything else
-- would quietly break packages that legitimately enumerate hardware.
do
  currentSeat = 2
  local comp = envFor().component
  eq("a geolyzer is still visible from any seat", "geo-1", joined(listAll(comp, "geolyzer")))
end

-- ── No resolvable seat = no narrowing at all ──────────────────────
-- This is the compatibility guarantee: single-seat machines, boot-time
-- code and off-box tests must see exactly what they always saw.
do
  currentSeat = nil
  local comp = envFor().component
  eq("with no seat, BOTH GPUs are visible", "gpu-1,gpu-2", joined(listAll(comp, "gpu")))
  test("with no seat, proxying any GPU works",
    (comp.proxy("gpu-1") or {}).address == "gpu-1")
  eq("with no seat, getPrimary falls back to the bus order",
    "gpu-1", (comp.getPrimary("gpu") or {}).address)
end

-- ── A seat whose GPU address can't be read narrows nothing ────────
-- Better to show too much than to show a program NO display at all.
do
  currentSeat = 2
  local saved = SEATS[2]
  SEATS[2] = { gpu = nil, screen = "screen-2", keyboards = { "kb-2" } }
  local comp = envFor().component
  eq("an unreadable seat GPU falls back to the full list",
    "gpu-1,gpu-2", joined(listAll(comp, "gpu")))
  SEATS[2] = saved
end

-- ── The kernel side really provides what the sandbox consults ─────
-- The stubs above define the contract; make sure the shipped screen.lua
-- actually offers it, or this whole mechanism is a no-op in production.
do
  local h = io.open("tos/kernel/screen.lua", "rb")
    or io.open("../../../tos/kernel/screen.lua", "rb")
  local src = h and h:read("*a")
  if h then h:close() end
  test("kernel/screen.lua readable", src ~= nil)
  if src then
    test("screen.callerDevices exists", src:find("function screen.callerDevices", 1, true) ~= nil)
    test("screen.seatDevices exists", src:find("function screen.seatDevices", 1, true) ~= nil)
    test("screen.callerSeat reads the process's display index",
      src:find("function screen.callerSeat", 1, true) ~= nil
      and src:find("p.display", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
