-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: netfsd serves what it says it serves         ║
-- ║                                                                ║
-- ║  20-netfsd runs as root, so rc.lua builds its env with         ║
-- ║  kernel.sandbox. That env has no _TOS, and its require refuses ║
-- ║  every "kernel." name -- so start() returned on its first line ║
-- ║  (no _TOS.net), and would have returned on its second (no      ║
-- ║  kernel.netfs). rc logged "Service started: 20-netfsd" and     ║
-- ║  listed it running; nothing ever called netfs.setEnabled(true).║
-- ║  Under that sat a second dead end: nothing in the kernel ever  ║
-- ║  called netfs.init, so even a loaded kernel.netfs had no net   ║
-- ║  to answer on, and the client half (`netfs mount`) timed out   ║
-- ║  with "no_network". test_netfs.lua drives a fake net and a     ║
-- ║  hand-made init, which is why neither showed.                  ║
-- ║                                                                ║
-- ║  So this drives every real piece: rc.lua loads the shipped     ║
-- ║  20-netfsd.lua into the real sandbox, on a machine whose net   ║
-- ║  is a real kernel.net, and a second real kernel.net mounts the ║
-- ║  export through the real netfs client, sealed, verified by     ║
-- ║  challenge-response, over a relayed modem.                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_netfsd_serves.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

local function readSrc(rel)
  for _, p in ipairs({ rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n")) end
  end
end
local function srcPath(rel)
  for _, p in ipairs({ rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then f:close(); return p end
  end
end

-- ── The wire ────────────────────────────────────────────────────────
-- Each machine's modem drops what it sends into its outbox; `relay`
-- carries those bytes to the other machine's net.handleIncoming. Every
-- wait in kernel.net ends in computer.pullSignal, so that is where the
-- relay runs -- the client's wait for NETFS_RES, and the server's own
-- wait for the challenge reply nested inside it.
local clock = 5
local relay = nil
package.loaded["computer"] = {
  uptime      = function() return clock end,
  freeMemory  = function() return 1e6 end,
  totalMemory = function() return 2e6 end,
  address     = function() return "test" end,
  pushSignal  = function() end,
  pullSignal  = function() clock = clock + 0.5; if relay then relay() end; return nil end,
}

local A_ADDR = "aaaa0000-0000-0000-0000-00000000000a"   -- mounts
local B_ADDR = "bbbb0000-0000-0000-0000-00000000000b"   -- serves
local SECRET = "0123456789abcdefghijklmnopqrstuv"

local quiet = function() end
local function makeNode(myAddr)
  local outbox = {}
  package.loaded["component"] = {
    list = function(t)
      local done = t ~= "modem"
      return function() if done then return nil end; done = true; return myAddr, "modem" end
    end,
    proxy = function() return {
      open = function() end, isWireless = function() return false end,
      send = function(to, _, data) outbox[#outbox + 1] = { to = to, data = data }; return true end,
      broadcast = function(_, data) outbox[#outbox + 1] = { to = "*", data = data }; return true end,
    } end,
    type = function() return nil end,
  }
  package.loaded["kernel.net.trust"] = nil   -- each machine its own trust DB
  local files = {}
  local net = dofile(srcPath("tos/kernel/net/init.lua"))
  net.init({
    log = { info = quiet, warn = quiet, debug = quiet, error = quiet },
    config = { get = function() return nil end, deviceType = function() return "computer" end },
    event = { on = quiet },
    fs = { exists = function(p) return files[p] ~= nil end,
           readFile = function(p) return files[p] end,
           writeFile = function(p, c) files[p] = c; return true end },
  })
  return net, outbox
end

local netA, outA = makeNode(A_ADDR)
local netB, outB = makeNode(B_ADDR)
for _, side in ipairs({ { netA, B_ADDR }, { netB, A_ADDR } }) do
  local trust = side[1].getTrust()
  assert(trust.setLevel("root", side[2], trust.LEVEL.TRUSTED, 3))
  assert(trust.setSecret("root", side[2], SECRET, 3))
end

relay = function()
  local moved = true
  while moved do
    moved = false
    local m = table.remove(outA, 1)
    if m then moved = true; netB.handleIncoming(A_ADDR, 42, 1, m.data) end
    m = table.remove(outB, 1)
    if m then moved = true; netA.handleIncoming(B_ADDR, 42, 1, m.data) end
  end
end

-- ── Machine A: the client half, wired by hand ───────────────────────
-- Loaded before B's _TOS exists, so this copy belongs to A alone and
-- B's kernel.netfs is whatever B's own boot makes of it.
local netfsA = dofile(srcPath("tos/kernel/netfs.lua"))
netfsA.init({ net = netA, trust = netA.getTrust(), computer = package.loaded["computer"],
              log = { info = quiet, warn = quiet } })
local share = netfsA.attach(B_ADDR, "pub")

local function readAll(path)
  local h = share.open(path, "r")
  if not h then return nil end
  local parts = {}
  while true do
    local c = share.read(h, 4096)
    if not c then break end
    parts[#parts + 1] = c
  end
  share.close(h)
  return table.concat(parts)
end

-- ── Machine B: boots its rc.d the way the kernel does ───────────────
local function ramFS()
  local files, dirs = {}, { ["/"] = true }
  local F = {}
  function F.normalize(p)
    if type(p) ~= "string" then return nil end
    local parts = {}
    for seg in p:gmatch("[^/]+") do
      if seg == ".." then
        if #parts > 0 then table.remove(parts) end
      elseif seg ~= "." then
        parts[#parts + 1] = seg
      end
    end
    return "/" .. table.concat(parts, "/")
  end
  function F.exists(p) return files[p] ~= nil or dirs[p] == true end
  function F.isDirectory(p) return dirs[p] == true end
  function F.size(p) return files[p] and #files[p] or 0 end
  function F.lastModified() return 7 end
  function F.spaceTotal() return 10000 end
  function F.spaceUsed() return 0 end
  function F.makeDirectory(p) dirs[p] = true; return true end
  function F.readFile(p) return files[p] end
  function F.writeFile(p, d) files[p] = d; return true end
  function F.remove(p) local had = files[p] ~= nil; files[p] = nil; return had end
  function F.list(p)
    local out = {}
    local prefix = p == "/" and "/" or (p .. "/")
    for k in pairs(files) do
      if k:sub(1, #prefix) == prefix and not k:sub(#prefix + 1):find("/") then
        out[#out + 1] = k:sub(#prefix + 1)
      end
    end
    table.sort(out)
    return out
  end
  function F.open(p, mode)
    if (mode or "r"):find("[wa]") or files[p] == nil then return nil, "not found" end
    local pos = 1
    return {
      read = function(_, n)
        local d = files[p]
        if pos > #d then return nil end
        local c = d:sub(pos, pos + n - 1); pos = pos + #c; return c
      end,
      close = function() return true end,
      seek  = function(_, _, off) pos = (tonumber(off) or 0) + 1; return pos - 1 end,
    }
  end
  return F
end

local EXPORTS = '{ { name = "pub", path = "/srv/pub", mode = "ro", allow = { "' .. A_ADDR .. '" } } }'
local FS = ramFS()
FS.makeDirectory("/etc"); FS.makeDirectory("/etc/rc.d")
FS.makeDirectory("/srv"); FS.makeDirectory("/srv/pub")
FS.writeFile("/srv/pub/hello.txt", "hello world")
FS.writeFile("/etc/netfs-exports.cfg", EXPORTS)
FS.writeFile("/etc/rc.d/20-netfsd.lua", assert(readSrc("etc/rc.d/20-netfsd.lua"), "20-netfsd.lua"))

local logged = {}
local function logLine(level)
  return function(src, msg) logged[#logged + 1] = level .. " " .. tostring(src) .. ": " .. tostring(msg) end
end
local logB = { info = logLine("info"), warn = logLine("warn"), debug = quiet, error = logLine("error") }
local function loggedMatching(pat)
  for _, l in ipairs(logged) do if l:find(pat) then return l end end
end

_G._TOS = {
  net = netB, fs = FS, logObj = logB, bootSession = {},
  securefs = { forSession = function() return FS end },
}
package.loaded["kernel.net"]     = netB
package.loaded["kernel.users"]   = { kernelSession = function() return {} end,
                                     sessionFor    = function() return { user = "root" } end }
package.loaded["kernel.sandbox"] = nil
package.loaded["kernel.netfs"]   = nil
package.loaded["kernel.rc"]      = nil
local rc = require("kernel.rc")
rc.init({ fs = FS, log = logB })

local function svc()
  for _, s in ipairs(rc.list()) do if s.name == "20-netfsd" then return s end end
end

print("=== netfsd serves what it says it serves ===")
print()
print("-- boot: the shipped service, through rc.lua, in the real sandbox --")
rc.runAll()
do
  local s = svc()
  test("rc lists 20-netfsd as running", s ~= nil and s.running == true, s and s.running)
  test("...as root, not kernel tier", s ~= nil and s.user == "root", s and s.user)
  test("...with no start failure logged", loggedMatching("20%-netfsd.*fail") == nil,
    loggedMatching("20%-netfsd.*fail"))
  test("...and it really armed the netfs backend", netB.getServiceArm("netfsd") == true,
    netB.getServiceArm("netfsd"))
  test("arming did not pull kernel.netfs into RAM at boot",
    package.loaded["kernel.netfs"] == nil)
end

print()
print("-- a TRUSTED peer mounts the export, over two real nets --")
do
  test("the peer sees /hello.txt on the share", share.exists("/hello.txt") == true)
  test("...reads it", readAll("/hello.txt") == "hello world", readAll("/hello.txt"))
  local names = share.list("/")
  test("...and lists it", names[1] == "hello.txt", names[1])
  local nf = package.loaded["kernel.netfs"]
  test("the first request loaded kernel.netfs on the server", nf ~= nil)
  test("...armed, by netfsd", nf ~= nil and nf.isEnabled() == true)
  test("...serving the export file's table", nf ~= nil and #nf.getExports() == 1
    and nf.getExports()[1].name == "pub")
end

print()
print("-- `service stop netfsd` stops the serving, not just the service --")
do
  local ok, err = rc.stop("20-netfsd")
  test("rc stops it", ok == true, err)
  local nf = package.loaded["kernel.netfs"]
  test("...disarmed in net", netB.getServiceArm("netfsd") == false)
  test("...and in the loaded backend", nf ~= nil and nf.isEnabled() == false)
  test("...its export table dropped", nf ~= nil and #nf.getExports() == 0)
  test("the peer can no longer read the file", readAll("/hello.txt") == nil)
end

print()
print("-- a rejected export file serves nothing, and a restart re-reads it --")
do
  FS.writeFile("/etc/netfs-exports.cfg", "{ this is not data")
  local ok, err = rc.start("20-netfsd")
  local nf = package.loaded["kernel.netfs"]
  test("the service starts (the arm is recorded)", ok == true, err)
  test("...but the backend stays disarmed", nf ~= nil and nf.isEnabled() == false)
  test("...with no export table left over from before", nf ~= nil and #nf.getExports() == 0)
  test("...and says why in the log", loggedMatching("netfs.*decode_failed") ~= nil)
  test("the peer is refused", readAll("/hello.txt") == nil)

  FS.writeFile("/etc/netfs-exports.cfg", EXPORTS)
  rc.stop("20-netfsd")
  ok, err = rc.start("20-netfsd")
  test("fix the file and restart: it serves again",
    ok == true and readAll("/hello.txt") == "hello world", err)

  -- Re-armed in place, with no stop between (the supervisor's restart,
  -- or anything else holding net): the table it was serving must go too.
  FS.writeFile("/etc/netfs-exports.cfg", "{ this is not data")
  netB.setServiceArm("netfsd", true)
  nf = package.loaded["kernel.netfs"]
  test("re-arming over a rejected file drops the table it was serving",
    nf ~= nil and #nf.getExports() == 0 and nf.isEnabled() == false)
  FS.writeFile("/etc/netfs-exports.cfg", EXPORTS)
end

print()
print("-- what the fix did NOT widen --")
do
  local sandbox = require("kernel.sandbox")
  local svcEnv = sandbox.build({ caps = { net = true }, allowUserLibs = true, session = {} })
  test("a root service's sandbox still refuses kernel.netfs",
    pcall(svcEnv.require, "kernel.netfs") == false)
  local progEnv = sandbox.build({ caps = { net = true }, session = {} })
  test("an ordinary program's `net` cannot arm netfsd",
    progEnv.net ~= nil and progEnv.net.setServiceArm == nil)
  local allow = rc._KERNEL_REQUIRE_ALLOW or {}
  test("kernel-tier require allowlist does not gain kernel.netfs", allow["kernel.netfs"] == nil)
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
