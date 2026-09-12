-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: compat names that are really capabilities     ║
-- ║                                                                ║
-- ║  The sandbox admits every "compat.*" name. Three of them were   ║
-- ║  authority, not libraries (Sep 2026 pentest):                   ║
-- ║   compat.component  OpenOS field access over the RAW component  ║
-- ║                     library -- .filesystem, .eeprom, .proxy --  ║
-- ║                     for any sandbox, no cap consulted.          ║
-- ║   compat.internet   the internet card, whatever the caps said.  ║
-- ║   compat            the loader: init()/setProcSleep() replace   ║
-- ║                     the os.sleep other programs call.           ║
-- ║  And shell.ext was on the ALLOWED list, though it is the body of║
-- ║  the net/hostname commands and writes the peer-alias table.     ║
-- ║                                                                ║
-- ║  Drives the REAL sandbox.build and its require.                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_compat_caps.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 500000 end,
  pushSignal = function() end, address = function() return "addr" end,
}
package.loaded["kernel.screen"] = {}                    -- no seats: nothing seat-filtered
package.loaded["kernel.fs"] = { exists = function() return false end }

-- A bus with one of everything that matters, and a record of what happened.
local ORDER = { "gpu1", "fs1", "ee1", "mod1", "inet1", "drv1" }
local DEVICES = { gpu1 = "gpu", fs1 = "filesystem", ee1 = "eeprom",
                  mod1 = "modem", inet1 = "internet", drv1 = "drive" }
local happened = {}
local proxies = {}
for addr, t in pairs(DEVICES) do
  proxies[addr] = { address = addr, type = t,
    remove = function(p) happened[#happened + 1] = t .. ".remove " .. tostring(p); return true end,
    set    = function() happened[#happened + 1] = t .. ".set"; return true end }
end
local rawComp = {
  list = function(filter, exact)
    local i = 0
    return function()
      while true do
        i = i + 1
        local a = ORDER[i]
        if not a then return nil end
        local t = DEVICES[a]
        if not filter or (exact and t == filter) or (not exact and t:find(filter, 1, true)) then
          return a, t
        end
      end
    end
  end,
  type  = function(a) return DEVICES[a] end,
  proxy = function(a) return proxies[a] end,
  slot  = function() return -1 end,
  get   = function(a) for k in pairs(DEVICES) do if k:sub(1, #a) == a then return k end end end,
  invoke = function() end,
  isAvailable = function(t) for _, v in pairs(DEVICES) do if v == t then return true end end return false end,
  getPrimary  = function(t) for _, a in ipairs(ORDER) do if DEVICES[a] == t then return proxies[a] end end end,
}
package.loaded["component"] = rawComp
-- compat.component exactly as compat/init.lua builds it: raw forwarding
-- plus OpenOS field access by type.
package.loaded["compat.component"] = setmetatable({}, { __index = function(_, key)
  if rawComp[key] ~= nil then return rawComp[key] end
  local addr = rawComp.list(key)()
  if addr then return rawComp.proxy(addr) end
end })
package.loaded["compat.internet"] = { request = function() return "fetched" end }
package.loaded["shell.ext"] = { net = function() happened[#happened + 1] = "ext.net"; return "ran" end }
local sleepHook = nil
package.loaded["compat"] = {
  has = function() return true end, list = function() return {} end,
  init = function(o) if o and o.procSleep then sleepHook = o.procSleep end end,
  setProcSleep = function(f) sleepHook = f end,
}

local sandbox = require("kernel.sandbox")
local function run(caps, src)
  local env = sandbox.build({ caps = caps })
  local fn = assert(load(src, "=probe", "t", env))
  local ok, err = pcall(fn)
  return env, ok, err
end

print("=== compat names that are capabilities ===")
print()

print("-- compat.component without the component cap --")
do
  local env = run({}, [[
    local ok, c = pcall(require, "compat.component")
    gotComp = ok and c ~= nil
    if gotComp then
      local fsP = c.filesystem; if fsP then fsP.remove("/init.lua") end
      local ee = c.eeprom;      if ee then ee.set("pwn") end
      gotDrive = c.proxy and c.proxy("drv1") ~= nil
    end
  ]])
  test("require('compat.component') is refused", env.gotComp == false)
  test("...so /init.lua was not removed through it", #happened == 0)
  test("...and no raw drive proxy came back", not env.gotDrive)
end

print("-- compat.component WITH the component cap --")
do
  local env, ok, err = run({ component = true }, [[
    c = require("compat.component")
    gpu, fsP, ee, modem = c.gpu, c.filesystem, c.eeprom, c.modem
    rawFs = c.proxy("fs1")
    rawGpu = c.proxy("gpu1")
    types = {}
    for _, t in c.list() do types[#types + 1] = t end
    wrote = pcall(function() c.proxy = function() end end)
    meta = getmetatable(c)
  ]])
  test("the probe ran (" .. tostring(err) .. ")", ok)
  test("field access still works for an allowed type (gpu)", env.gpu ~= nil)
  test("...but not for a filesystem", env.fsP == nil)
  test("...nor the EEPROM", env.ee == nil)
  test("...nor a gated type whose cap is missing (modem)", env.modem == nil)
  test("proxy() refuses a filesystem address", env.rawFs == nil)
  test("proxy() still serves the gpu", env.rawGpu ~= nil)
  test("list() shows only what the caps allow", #env.types == 1 and env.types[1] == "gpu")
  test("the view is read-only", env.wrote == false)
  test("its metatable is locked", env.meta == false)
end

print("-- compat.internet --")
do
  local env = run({ ["compat.io"] = true }, [[
    local ok = pcall(require, "compat.internet"); got = ok ]])
  test("refused without the internet cap", env.got == false)
  local env2 = run({ internet = true }, [[ got = require("compat.internet").request() ]])
  test("served with the internet cap", env2.got == "fetched")
end

print("-- shell.ext --")
do
  local env = run({}, [[ local ok = pcall(require, "shell.ext"); got = ok ]])
  test("shell.ext is not requirable from a sandbox", env.got == false)
end

print("-- the compat loader --")
do
  local env = run({}, [[
    local c = require("compat")
    hasInit, hasSet, hasList = c.init ~= nil, c.setProcSleep ~= nil, c.list ~= nil
    if c.init then c.init({ procSleep = function() end }) end
    if c.setProcSleep then c.setProcSleep(function() end) end
  ]])
  test("a sandbox's compat has no init()", env.hasInit == false)
  test("...and no setProcSleep()", env.hasSet == false)
  test("...but still has list()", env.hasList == true)
  test("the shared os.sleep hook was not replaced", sleepHook == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
