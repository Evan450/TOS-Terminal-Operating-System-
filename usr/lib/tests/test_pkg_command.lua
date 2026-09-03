-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: pkg command dispatch (modules pivot)║
-- ║  - pkg.getCommand loads a package entry in a sandbox   ║
-- ║    and returns its command fn                           ║
-- ║  - disabled / unknown commands return nil               ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_command.lua

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

-- The demo package's entry source: returns the module-style shape that
-- kernel.modules and pkg both expect.
local ENTRY_SRC = [[
return { commands = { hello = function(args, o) if o then o("HELLO") end; return "ran" end } }
]]

local DEMO = {
  name = "demo", version = "1.0", kind = "command",
  files = { "/usr/modules/demo/init.lua" },
  commands = { hello = "/usr/modules/demo/init.lua" },
  -- Includes "legacy" to prove the allowlist drops it.
  capabilities = { "fs.read", "legacy", "component" },
}

-- Stubs: serialize (loadFile returns the manifest), sandbox (empty env is
-- fine — the entry source needs no globals), users (no session).
package.loaded["kernel.serialize"] = {
  encode = function() return "" end, decode = function() return nil end,
  saveFile = function() return true end,
  loadFile = function(_, path)
    if path:find("demo/package.lua", 1, true) then return DEMO end
    return nil
  end,
}
local lastCaps
package.loaded["kernel.sandbox"] = {
  build = function(opts) lastCaps = opts and opts.caps or {}; return {} end,
}
package.loaded["kernel.users"]   = { currentSession = function() return nil end }

-- Mock fs (high-level kernel.fs surface pkg uses).
local STATE_DISABLED = false
local fsMock = {
  exists = function(p)
    if p:find("/state", 1, true) then return STATE_DISABLED end  -- absent => enabled
    return true
  end,
  isDirectory   = function() return true end,
  makeDirectory = function() return true end,
  list = function(p) if p == "/var/pkg/installed" then return { "demo" } end return {} end,
  join = function(...) return table.concat({ ... }, "/") end,
  normalize = function(p) return p end,
  readFile  = function(p)
    if p == "/usr/modules/demo/init.lua" then return ENTRY_SRC end
    if p:find("/state", 1, true) then return STATE_DISABLED and "d" or "e" end
    return nil
  end,
  writeFile = function() return true end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_command.lua"
local base = here:gsub("[^/\\]*$", "")
local pkg
for _, p in ipairs({ base .. "../../../tos/kernel/pkg.lua", "tos/kernel/pkg.lua",
    "TOS-Dev/tos/kernel/pkg.lua" }) do
  local chunk = loadfile(p)
  if chunk then pkg = chunk(); break end
end
if not pkg then
  print("FAIL: could not load pkg.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

pkg.init({ fs = fsMock, log = nil, users = package.loaded["kernel.users"] })

print("=== pkg command dispatch Tests ===")
print()

-- The package scanned in?
test("demo package scanned", "demo", (pkg.info("demo") or {}).name)
test("commands() exposes hello -> path", "/usr/modules/demo/init.lua",
  (pkg.commands() or {}).hello)

-- getCommand returns a runnable function.
local fn = pkg.getCommand("hello")
test("getCommand('hello') returns a function", "function", type(fn))
test("the resolved command runs", "ran", fn and fn({}, nil))

-- Output is routed through the supplied sink.
local out = {}
if fn then fn({}, function(line) out[#out + 1] = line end) end
test("command writes via the o() sink", "HELLO", out[1])

-- #SEC — capability allowlist: declared caps reach the sandbox, but the
-- dangerous "legacy" facet is dropped.
test("allowed cap 'fs.read' passed to sandbox", true, lastCaps and lastCaps["fs.read"] == true)
test("allowed cap 'component' passed", true, lastCaps and lastCaps.component == true)
test("dangerous 'legacy' cap DROPPED", nil, lastCaps and lastCaps.legacy)

-- Unknown command -> nil.
test("getCommand('nope') -> nil", nil, pkg.getCommand("nope"))

-- Disabled package -> command not resolved.
STATE_DISABLED = true
pkg.flushCommandCache()           -- drop the cached entry
pkg.scan()                        -- re-scan picks up the (now disabled) state
test("disabled package hides its command", nil, pkg.getCommand("hello"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
