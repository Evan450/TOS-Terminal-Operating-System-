-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a sandbox cannot rewrite a shared module      ║
-- ║                                                                ║
-- ║  H4 gave sandboxes a COPY of a listed set of compat.* modules.  ║
-- ║  Everything else came back as the very table the kernel and the ║
-- ║  shell use -- shell.keys, peripheral.*, compat.shell_api, every ║
-- ║  installed library -- and build() put compat.io,                ║
-- ║  compat.filesystem and kernel.net into the env uncopied. So     ║
-- ║  `require("shell.keys").is = f` ran f in every other seat's     ║
-- ║  shell process (keys.is is called per keystroke), and           ║
-- ║  `net.send = f` ran f inside kernel services as _kernel_.       ║
-- ║                                                                ║
-- ║  Drives the REAL sandbox.build and its require against the real ║
-- ║  package.loaded tables the rest of the system would read.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_module_isolation.lua   (from TOS-Dev)

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
package.loaded["component"] = {
  list = function() return function() end end, proxy = function() end,
}

-- The shared tables, as package.loaded holds them for everyone.
local real = {
  ["shell.keys"]          = { is = function() return "real" end, DEFAULTS = { quit = { "^Q" } } },
  ["kernel.net"]          = { send = function() return "real" end },
  ["compat.io"]           = { open = function() return "real" end },
  ["compat.filesystem"]   = { list = function() return "real" end },
  ["compat.shell_api"]    = { execute = function() return "real" end },
  ["peripheral.redstone"] = { setOutput = function() return "real" end },
  ["blockfs"]             = { mount = function() return "real" end },
  ["compat.term"]         = { _gpuForCaps = function(c) return (c and c.gpu) and "rw" or "ro" end },
}
for name, t in pairs(real) do package.loaded[name] = t end
-- blockfs is an installed library: the sandbox finds it under /usr/lib and
-- (since the pentest's user-lib fix) loads its OWN instance from the file,
-- so the kernel's table in package.loaded is never what a sandbox holds.
package.loaded["kernel.fs"] = {
  exists   = function(p) return p == "/usr/lib/blockfs.lua" end,
  readFile = function(p)
    if p == "/usr/lib/blockfs.lua" then
      return 'return { mount = function() return "real" end }'
    end
  end,
}

local sandbox = require("kernel.sandbox")
local function build(extra)
  local opts = { caps = { ["compat.io"] = true, net = true } }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return sandbox.build(opts)
end

local ATTACK = [[
  require("shell.keys").is = function() return "evil" end
  net.send = function() return "evil" end
  io.open = function() return "evil" end
  filesystem.list = function() return "evil" end
  require("compat.shell_api").execute = function() return "evil" end
  require("peripheral.redstone").setOutput = function() return "evil" end
  require("blockfs").mount = function() return "evil" end
  local _, orig = pairs(require("shell.keys"))
  leaked = orig
  metaSeen = getmetatable(require("shell.keys"))
  relock = pcall(setmetatable, require("shell.keys"), {})
  ownView = require("shell.keys").is()
  local n = 0
  for _ in pairs(require("shell.keys")) do n = n + 1 end
  walked = n
  gpu = require("compat.term").gpu()
]]

print("=== sandbox module isolation ===")
print()
local env = build()
local fn = assert(load(ATTACK, "=attack", "t", env))
local ok, err = pcall(fn)
test("the attack script ran (" .. tostring(err) .. ")", ok)

print("-- the shared tables are untouched --")
test("shell.keys.is", real["shell.keys"].is() == "real")
test("kernel.net.send", real["kernel.net"].send() == "real")
test("compat.io.open", real["compat.io"].open() == "real")
test("compat.filesystem.list", real["compat.filesystem"].list() == "real")
test("compat.shell_api.execute", real["compat.shell_api"].execute() == "real")
test("peripheral.redstone.setOutput", real["peripheral.redstone"].setOutput() == "real")
test("an installed library (blockfs.mount)", real["blockfs"].mount() == "real")

print("-- the view does not hand the original back --")
test("pairs() does not return the original table", env.leaked == nil)
test("getmetatable() does not return a way in", env.metaSeen == false or env.metaSeen == nil)
test("setmetatable() on a view is refused", env.relock == false)

print("-- and it still behaves like the module --")
test("the sandbox sees its own write", env.ownView == "evil")
test("pairs() still walks the module's fields", (env.walked or 0) >= 2)
test("compat.term's gpu() is still bound to the sandbox's caps", env.gpu == "ro")
real["shell.keys"].added = 42
test("a field the module gains later is visible (a view, not a stale copy)",
  env.require("shell.keys").added == 42)
local env2 = build()
test("a second sandbox never sees the first one's writes", env2.require("shell.keys").is() == "real")

print("-- an rc.d service keeps its own library's real table --")
local svc = sandbox.build({ caps = { ["fs.read"] = true }, allowUserLibs = true })
test("allowUserLibs: require('blockfs') is the shared table", svc.require("blockfs") == real["blockfs"])

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
