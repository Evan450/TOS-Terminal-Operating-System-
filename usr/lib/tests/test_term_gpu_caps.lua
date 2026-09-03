-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: term.gpu() Cap Gating (CR-8)       ║
-- ║  - mutating ops denied without a display cap          ║
-- ║  - read-only queries always pass                      ║
-- ║  - _gpuForCaps grants mutation with caps.gpu/display  ║
-- ║  - GPU resolved via display.getGpu() (seat-bound)     ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_term_gpu_caps.lua

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

-- Fake seat GPU that records whether mutating methods were actually hit.
local hits = {}
local fakeGpu = {
  getResolution = function() return 80, 25 end,
  getDepth      = function() return 8 end,
  set  = function() hits.set  = true; return true end,
  fill = function() hits.fill = true; return true end,
  bind = function() hits.bind = true; return true end,
}
package.loaded["kernel.display"] = {
  getGpu  = function() return fakeGpu end,
  getSize = function() return 80, 25 end,
}
package.loaded["computer"]  = { uptime = function() return 0 end }
package.loaded["component"] = {
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_term_gpu_caps.lua"
local base = here:gsub("[^/\\]*$", "")
local term
for _, p in ipairs({ base .. "../../../tos/compat/term.lua", "tos/compat/term.lua",
    "TOS-Dev/tos/compat/term.lua" }) do
  local chunk = loadfile(p)
  if chunk then term = chunk(); break end
end
if not term then
  print("FAIL: could not load term.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== term.gpu() Capability Gating Tests ===")
print()

-- Default term.gpu(): read-only.
local g = term.gpu()
test("term.gpu() returns a proxy", true, type(g) == "table")
local w, h = g.getResolution()
test("read-only getResolution works", true, w == 80 and h == 25)

hits = {}
local okSet, errSet = g.set(1, 1, "x")
test("set() denied without cap", false, okSet)
test("set() denial has a reason", true, type(errSet) == "string")
test("real gpu.set NOT called", nil, hits.set)

local okBind = g.bind("addr")
test("bind() denied without cap", false, okBind)
test("real gpu.bind NOT called", nil, hits.bind)

-- _gpuForCaps with no caps: still read-only.
local gNo = term._gpuForCaps({})
test("no-caps proxy denies fill", false, (gNo.fill(1, 1, 1, 1, " ")))

-- _gpuForCaps with display cap: mutation allowed.
hits = {}
local gCap = term._gpuForCaps({ gpu = true })
local okC = gCap.set(1, 1, "y")
test("capped proxy allows set", true, okC)
test("real gpu.set called with cap", true, hits.set)

-- caps.display also works.
hits = {}
local gCap2 = term._gpuForCaps({ display = true })
gCap2.fill(1, 1, 80, 25, " ")
test("caps.display allows fill", true, hits.fill == true)

-- Read still works on capped proxy.
test("capped proxy read still works", 8, (gCap.getDepth()))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
