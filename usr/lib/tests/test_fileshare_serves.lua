-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: fileshare answers the FILE_REQ it armed for  ║
-- ║                                                                ║
-- ║  kernel.net.transfer is not loaded at boot: net's dispatch     ║
-- ║  lazy-loads it on the first inbound FILE_REQ, and its          ║
-- ║  self-init registers the listener that answers. But dispatch   ║
-- ║  only tried that load when NO listener existed for the type,   ║
-- ║  and 20-fileshare's start() registers one of its own -- a      ║
-- ║  logger. So on every boot the first FILE_REQ found the logger, ║
-- ║  transfer never loaded, the request was logged and dropped,    ║
-- ║  and the peer timed out. rc listed fileshare running and net   ║
-- ║  had it armed. It served only on a machine that had already    ║
-- ║  loaded transfer some other way (an outbound scp).             ║
-- ║                                                                ║
-- ║  So this drives every real piece: rc.lua loads the shipped     ║
-- ║  20-fileshare.lua as a kernel-tier service on a machine whose  ║
-- ║  net is a real kernel.net, and a second real kernel.net asks   ║
-- ║  for a /public/ file through the real transfer client, sealed  ║
-- ║  and challenge-verified, over a relayed modem.                 ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_fileshare_serves.lua   (from TOS-Dev)

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

-- Every time require has to actually LOAD a lazy backend (it is not in
-- package.loaded yet), this searcher runs first and counts it. A load
-- that is repeated per packet, or retried after a failure, shows here.
local LAZY = { ["kernel.net.transfer"] = true, ["kernel.net.remote"] = true,
               ["kernel.netfs"] = true }
local loads = {}
table.insert(package.searchers, 1, function(name)
  if LAZY[name] then loads[name] = (loads[name] or 0) + 1 end
  return nil
end)

-- ── The wire ────────────────────────────────────────────────────────
-- Each machine's modem drops what it sends into its outbox; `relay`
-- carries those bytes to the other machine's net.handleIncoming. Every
-- wait in kernel.net ends in computer.pullSignal, so that is where the
-- relay runs -- the client's wait for FILE_RES, and the server's own
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

local A_ADDR = "aaaa0000-0000-0000-0000-00000000000a"   -- asks
local B_ADDR = "bbbb0000-0000-0000-0000-00000000000b"   -- serves
local SECRET = "0123456789abcdefghijklmnopqrstuv"

local quiet = function() end
-- B's log (its net, its rc, transfer's self-init) is kept and searched.
local logged = {}
local function logLine(level)
  return function(src, msg) logged[#logged + 1] = level .. " " .. tostring(src) .. ": " .. tostring(msg) end
end
local logB = { info = logLine("info"), warn = logLine("warn"), debug = quiet, error = logLine("error") }
local function loggedMatching(pat)
  for _, l in ipairs(logged) do if l:find(pat) then return l end end
end
local function countLogged(pat)
  local n = 0
  for _, l in ipairs(logged) do if l:find(pat) then n = n + 1 end end
  return n
end

local function makeNode(myAddr, netLog)
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
    log = netLog or { info = quiet, warn = quiet, debug = quiet, error = quiet },
    config = { get = function() return nil end, deviceType = function() return "computer" end },
    event = { on = quiet },
    fs = { exists = function(p) return files[p] ~= nil end,
           readFile = function(p) return files[p] end,
           writeFile = function(p, c) files[p] = c; return true end },
  })
  return net, outbox
end

local netA, outA = makeNode(A_ADDR)
local netB, outB = makeNode(B_ADDR, logB)
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

-- ── A small RAM filesystem, one per machine ─────────────────────────
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
  return F
end

-- ── Machine A: the client half (what `scp` calls), wired by hand ────
-- Loaded before B's _TOS exists, so this copy belongs to A alone and
-- B's kernel.net.transfer is whatever B's own dispatch makes of it.
local FS_A = ramFS()
FS_A.makeDirectory("/tmp")
local transferA = dofile(srcPath("tos/kernel/net/transfer.lua"))
transferA.init({ net = netA, fs = FS_A, trust = netA.getTrust(),
                 log = { info = quiet, warn = quiet } })

local function fetch(remotePath, localPath)
  FS_A.remove(localPath)
  local ok, err = transferA.request(B_ADDR, remotePath, localPath)
  return ok, err, FS_A.readFile(localPath)
end

-- ── Machine B: boots its rc.d the way the kernel does ───────────────
local FS = ramFS()
FS.makeDirectory("/etc"); FS.makeDirectory("/etc/rc.d")
FS.makeDirectory("/public")
FS.writeFile("/public/hello.txt", "hello world")
FS.writeFile("/etc/secret.txt", "not for peers")
FS.writeFile("/etc/rc.d/20-fileshare.lua",
  assert(readSrc("etc/rc.d/20-fileshare.lua"), "20-fileshare.lua"))

-- transfer's self-init reads net/fs/securefs/users/logObj off _TOS;
-- 20-fileshare's logger calls _TOS.log.
_G._TOS = {
  net = netB, fs = FS, logObj = logB, log = logLine("svc"), bootSession = {},
  securefs = { forSession = function() return FS end },
  users = { currentSession = function() return { user = "root" } end },
}
package.loaded["kernel.net"]          = netB
package.loaded["kernel.users"]        = { kernelSession = function() return {} end,
                                          sessionFor    = function() return { user = "root" } end }
package.loaded["kernel.net.transfer"] = nil
package.loaded["kernel.net.remote"]   = nil
package.loaded["kernel.netfs"]        = nil
package.loaded["kernel.rc"]           = nil
local rc = require("kernel.rc")
rc.init({ fs = FS, log = logB })

local function svc()
  for _, s in ipairs(rc.list()) do if s.name == "20-fileshare" then return s end end
end

print("=== fileshare answers the FILE_REQ it armed for ===")
print()
print("-- boot: the shipped service, through rc.lua, kernel tier --")
rc.runAll()
do
  local s = svc()
  test("rc lists 20-fileshare as running", s ~= nil and s.running == true, s and s.running)
  test("...at kernel tier", s ~= nil and s.user == "_kernel_", s and s.user)
  test("...with no start failure logged", loggedMatching("20%-fileshare.*fail") == nil,
    loggedMatching("20%-fileshare.*fail"))
  test("...and it armed the transfer backend", netB.getServiceArm("fileshare") == true,
    netB.getServiceArm("fileshare"))
  test("arming did not pull kernel.net.transfer into RAM at boot",
    package.loaded["kernel.net.transfer"] == nil)
end

print()
print("-- a TRUSTED peer asks for a /public/ file, over two real nets --")
do
  local ok, err, got = fetch("/public/hello.txt", "/tmp/hello.txt")
  test("the first FILE_REQ after boot is answered", ok == true, err)
  test("...with the file's contents", got == "hello world", got)
  local T = package.loaded["kernel.net.transfer"]
  test("that request loaded kernel.net.transfer on the server", T ~= nil)
  test("...armed, by fileshare", T ~= nil and T.isEnabled() == true)
  test("fileshare's own logger still saw it",
    loggedMatching("svc fileshare: File request from aaaa0000: /public/hello.txt") ~= nil)

  ok, err, got = fetch("/public/hello.txt", "/tmp/again.txt")
  test("a second request is answered too", ok == true and got == "hello world", err)
  test("...and logged once more, not twice per request",
    countLogged("svc fileshare: File request from") == 2, countLogged("svc fileshare: File request from"))

  ok, err = fetch("/etc/secret.txt", "/tmp/secret.txt")
  test("a path outside /public/ is still refused", ok == false
    and tostring(err):find("restricted to /public/", 1, true) ~= nil, err)
end

print()
print("-- `service stop fileshare` stops the serving, not just the logger --")
do
  local ok, err = rc.stop("20-fileshare")
  local T = package.loaded["kernel.net.transfer"]
  test("rc stops it", ok == true, err)
  test("...disarmed in net", netB.getServiceArm("fileshare") == false)
  test("...and in the loaded backend", T ~= nil and T.isEnabled() == false)
  local okF, errF, got = fetch("/public/hello.txt", "/tmp/stopped.txt")
  test("the peer is no longer served", okF == false and got == nil, errF)

  ok, err = rc.start("20-fileshare")
  okF, errF, got = fetch("/public/hello.txt", "/tmp/back.txt")
  test("start it again: it serves again", ok == true and okF == true and got == "hello world",
    tostring(err) .. " / " .. tostring(errF))
end

print()
print("-- each lazy backend loads exactly once --")
do
  local P = netA.getProtocol()
  for _ = 1, 3 do
    netA.send(B_ADDR, P.makePacket(P.TYPE.REMOTE_EXEC, { cmd = "true" }, { to = B_ADDR }))
    netA.send(B_ADDR, P.makePacket(P.TYPE.NETFS_REQ, { op = "stat", share = "x", path = "/" },
      { to = B_ADDR }))
    relay()
  end
  test("kernel.net.transfer: one load across five FILE_REQs", loads["kernel.net.transfer"] == 1,
    loads["kernel.net.transfer"])
  test("kernel.net.remote: one load across three REMOTE_EXECs", loads["kernel.net.remote"] == 1,
    loads["kernel.net.remote"])
  test("kernel.netfs: one load across three NETFS_REQs", loads["kernel.netfs"] == 1,
    loads["kernel.netfs"])
  test("...and none of them failed to load", loggedMatching("Lazy handler load failed") == nil,
    loggedMatching("Lazy handler load failed"))
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
