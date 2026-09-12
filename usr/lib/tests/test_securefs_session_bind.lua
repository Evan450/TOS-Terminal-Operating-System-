-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what a sandboxed program's `fs` can reach     ║
-- ║                                                                ║
-- ║  Four holes from the Sep 2026 pentest, all reachable by any     ║
-- ║  program holding only `fs.read`:                               ║
-- ║   1. forSession appended the bound session AFTER the caller's   ║
-- ║      arguments, so fs.readFile(p, {tier = 3}) ran as root.      ║
-- ║   2. open() returned kernel.fs's handle, `proxy` and all -- the ║
-- ║      raw filesystem component, no ACL anywhere below it.        ║
-- ║   3. open() treated any mode without w/a/+ as a read; TBFS      ║
-- ║      opens every mode but "r" writable, so "x" wrote the kernel.║
-- ║   4. copy() of a directory checked the top path, then walked    ║
-- ║      the raw tree: `cp /home ~/x` took every user's files.      ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.fs, kernel.users, kernel.securefs and   ║
-- ║  kernel.sandbox together over an in-memory disk, because every  ║
-- ║  one of these lived at a seam between two of them.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_securefs_session_bind.lua   (from TOS-Dev)

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
-- The acting principal, as the scheduler would report it.
local CURRENT = nil
package.loaded["kernel.process"] = {
  currentSession   = function() return CURRENT end,
  currentToken     = function() return nil end,
  yieldCooperative = function() end,
}
package.loaded["kernel.crypto"] = {
  init = function() end,
  salt = function() return "SALT" end,
  hashPassword = function(pw, salt) return "H:" .. tostring(salt) .. "|" .. tostring(pw) end,
  verifyPassword = function(pw, salt, hash)
    return hash == "H:" .. tostring(salt) .. "|" .. tostring(pw), false
  end,
  token = (function() local n = 0; return function() n = n + 1; return "tok" .. n end end)(),
  hasHardware = function() return false end,
}

-- ── An in-memory disk with TBFS's open() semantics ─────────────────
-- blockfs P.open: strip "b"; exactly "r" reads; ANY other mode string
-- opens the file writable (creating it if absent). A write budget turns
-- a runaway recursive copy into a bounded failure instead of a hang.
local files, dirs = {}, { ["/"] = true }
local handles, nextH, created = {}, 1, 0
local function clean(p)
  p = p or "/"
  if #p > 1 then p = p:gsub("/+$", "") end
  return p == "" and "/" or p
end
local function parentOf(p) local d = p:match("^(.*)/[^/]+$"); return (d == "" or not d) and "/" or d end
local disk = { address = "disk0" }
function disk.exists(p) p = clean(p); return files[p] ~= nil or dirs[p] ~= nil end
function disk.isDirectory(p) return dirs[clean(p)] == true end
function disk.list(p)
  p = clean(p); if not dirs[p] then return nil end
  local prefix, out = (p == "/") and "/" or (p .. "/"), {}
  for f in pairs(files) do
    local rest = f:sub(1, #prefix) == prefix and f:sub(#prefix + 1)
    if rest and rest ~= "" and not rest:find("/") then out[#out + 1] = rest end
  end
  for d in pairs(dirs) do
    local rest = d ~= p and d:sub(1, #prefix) == prefix and d:sub(#prefix + 1)
    if rest and rest ~= "" and not rest:find("/") then out[#out + 1] = rest .. "/" end
  end
  table.sort(out)
  return out
end
function disk.makeDirectory(p)
  p = clean(p)
  if dirs[p] or files[p] or not dirs[parentOf(p)] then return false end
  dirs[p] = true; return true
end
function disk.open(p, mode)
  p = clean(p); mode = (mode or "r"):gsub("b", "")
  if mode == "r" then
    if not files[p] then return nil, p end
  else
    if not files[p] then
      created = created + 1
      if created > 2000 then return nil, "disk full" end
      if not dirs[parentOf(p)] then return nil, "no parent" end
      files[p] = ""
    end
    if mode == "w" then files[p] = "" end
  end
  local h = nextH; nextH = nextH + 1
  handles[h] = { path = p, mode = mode, pos = (mode == "a") and #files[p] or 0 }
  return h
end
function disk.read(h, n)
  local st = handles[h]; if not st then return nil, "bad handle" end
  local data = files[st.path] or ""
  if st.pos >= #data then return nil end
  local chunk = data:sub(st.pos + 1, st.pos + (n or 4096))
  st.pos = st.pos + #chunk
  return chunk
end
function disk.write(h, d)
  local st = handles[h]; if not st then return false, "bad handle" end
  if st.mode == "r" then return false, "read-only handle" end
  local cur = files[st.path] or ""
  files[st.path] = cur:sub(1, st.pos) .. d .. cur:sub(st.pos + #d + 1)
  st.pos = st.pos + #d
  return true
end
function disk.seek(h, whence, off)
  local st = handles[h]; if not st then return nil end
  off = off or 0
  if whence == "set" then st.pos = off elseif whence == "cur" then st.pos = st.pos + off
  elseif whence == "end" then st.pos = #(files[st.path] or "") + off end
  return st.pos
end
function disk.close(h) handles[h] = nil; return true end
function disk.remove(p)
  p = clean(p)
  if files[p] then files[p] = nil; return true end
  if dirs[p] and p ~= "/" then
    local prefix = p .. "/"
    for f in pairs(files) do if f:sub(1, #prefix) == prefix then files[f] = nil end end
    for d in pairs(dirs) do if d:sub(1, #prefix) == prefix then dirs[d] = nil end end
    dirs[p] = nil; return true
  end
  return false
end
function disk.rename(a, b)
  a, b = clean(a), clean(b)
  if files[a] then files[b] = files[a]; files[a] = nil; return true end
  return false
end
function disk.size(p) local f = files[clean(p)]; return f and #f or 0 end
function disk.lastModified() return 0 end
function disk.spaceTotal() return 1e7 end
function disk.spaceUsed() return 0 end
function disk.getLabel() return "test" end

local function raw(p) return files[p] end

-- ── Boot the real modules ──────────────────────────────────────────
local fs = require("kernel.fs")
fs.init(disk)
local users = require("kernel.users")
_G._TOS = { bootSession = users.kernelSession() }   -- kernel-boot context
users.init({ fs = fs, crypto = package.loaded["kernel.crypto"], log = nil })
local T = users.TIER
assert(users.create("root", "alice", "alicepw1", T.USER))
assert(users.create("root", "bob",   "bobpw123", T.USER))
assert(users.create("root", "adam",  "adampw12", T.ADMIN))
assert(users.create("root", "rooty", "rootypw1", T.ROOT))
assert(users.create("root", "carol", "carolpw1", T.USER))
_G._TOS.bootSession, _G._TOS.bootCompleted = nil, true

local securefs = require("kernel.securefs")
securefs.init({ fs = fs, users = users, log = nil, process = package.loaded["kernel.process"] })
_G._TOS.securefs, _G._TOS.users = securefs, users

-- fs.writeFile makes only the immediate parent (as OC's proxy does), so
-- the deeper directories are made first or the files never exist -- and
-- a check that the kernel "is still there" would pass on nothing.
for _, d in ipairs({ "/tos/kernel", "/var/log", "/var/pkg/secrets", "/var/pkg/installed/mail" }) do
  fs.makeDirectory(d)
end
fs.writeFile("/etc/motd", "hi")
fs.writeFile("/etc/trust.dat", "SECRET-TRUST")
fs.writeFile("/etc/elevate.dat", "ELEV-HASH")
fs.writeFile("/tos/kernel/init.lua", "KERNEL")
fs.writeFile("/home/bob/diary.txt", "bob private")
fs.writeFile("/home/alice/own.txt", "mine")
fs.writeFile("/var/log/kernel.log", "[auth] Login attempt for unknown user: hunter2")
fs.writeFile("/var/pkg/secrets/mail", "PKG-SECRET-0123456789")
fs.writeFile("/var/pkg/installed/mail/package.lua", "return {}")
local shadow = raw("/etc/users.dat")
assert(shadow and #shadow > 0, "setup: users.dat was not written")

local aliceS = users.sessionFor("alice")
local adamS  = users.sessionFor("adam")
local guestS = { user = "guest", tier = T.GUEST, home = "/public" }
local forged = { user = "root", tier = T.ROOT, home = "/root" }

local sandbox = require("kernel.sandbox")
local envR = sandbox.build({ caps = { ["fs.read"] = true }, session = aliceS })
local envW = sandbox.build({ caps = { ["fs.read"] = true, ["fs.write"] = true }, session = aliceS })

print("=== securefs: what a sandboxed fs can reach ===")
print()

print("-- 1. a caller cannot supply its own session --")
test("fs.read: a forged session does not read the shadow",
  envR.fs.readFile("/etc/users.dat", forged) == nil)
test("fs.read: ...nor another user's home",
  envR.fs.readFile("/home/bob/diary.txt", forged) == nil)
test("fs.read: ...nor probe it with exists()",
  envR.fs.exists("/home/bob/diary.txt", forged) == false)
test("fs.read: open() with a forged session is refused too",
  envR.fs.open("/etc/users.dat", "r", forged) == nil)
envW.fs.writeFile("/etc/users.dat", "root = pwned", forged)
test("fs.write: a forged session does not rewrite the shadow", raw("/etc/users.dat") == shadow)
envW.fs.appendFile("/home/bob/diary.txt", " +alice", forged)
test("fs.write: ...nor append to another user's file", raw("/home/bob/diary.txt") == "bob private")
test("honest reads still work", envR.fs.readFile("/home/alice/own.txt") == "mine")
test("honest writes still work",
  envW.fs.writeFile("/home/alice/new.txt", "ok") and raw("/home/alice/new.txt") == "ok")
do
  local p = securefs.forSession(aliceS)
  test("forSession proxy: trailing argument ignored",
    p.readFile("/etc/users.dat", forged) == nil)
  test("forSession proxy: home() is the bound session's",
    p.home(forged) == "/home/alice")
end

print()
print("-- 2. an open handle is four methods, not the disk --")
do
  local h = envR.fs.open("/etc/motd", "r")
  test("open returns a handle", type(h) == "table")
  local extras = {}
  for k in pairs(h or {}) do
    if k ~= "read" and k ~= "write" and k ~= "seek" and k ~= "close" then
      extras[#extras + 1] = tostring(k)
    end
  end
  test("the handle carries nothing but read/write/seek/close ("
    .. (#extras > 0 and table.concat(extras, ",") or "none") .. ")", #extras == 0)
  test("h.proxy is not the raw filesystem", h and h.proxy == nil)
  if h and type(h.proxy) == "table" and h.proxy.remove then h.proxy.remove("/tos/kernel/init.lua") end
  test("...and the kernel is still there", raw("/tos/kernel/init.lua") == "KERNEL")
  test("the handle still reads", h and h:read(100) == "hi")
  if h then h:close() end
end

print()
print("-- 3. open modes are a closed set --")
do
  local hx = envR.fs.open("/tos/kernel/init.lua", "x")
  if hx then pcall(function() hx:write("PWNED"); hx:close() end) end
  test("fs.read: mode 'x' does not reach TBFS as a writer", hx == nil)
  test("...and the kernel is unchanged", raw("/tos/kernel/init.lua") == "KERNEL")
  test("mode 'W' is refused", envW.fs.open("/home/alice/own.txt", "W") == nil)
  test("mode 'r+' is refused", envW.fs.open("/home/alice/own.txt", "r+") == nil)
  -- Refused, not raised: the old test called mode:find() and threw.
  local okT, hT = pcall(envW.fs.open, "/home/alice/own.txt", {})
  test("a non-string mode is refused (not raised)", okT and hT == nil)
  local hb = envR.fs.open("/etc/motd", "rb")
  test("'rb' still reads", hb ~= nil and hb:read(10) == "hi")
  local hw = envW.fs.open("/home/alice/w.txt", "wb")
  test("'wb' still writes", hw ~= nil and hw:write("x") and raw("/home/alice/w.txt") == "x")
end

print()
print("-- 4. a directory copy is checked per entry --")
do
  -- Into /tmp, not ~: the old copy-into-itself guard happened to stop
  -- /home -> ~/loot, and never stopped /home -> /tmp/loot.
  securefs.copy("/home", "/tmp/loot", aliceS)
  test("cp /home does not take bob's files", raw("/tmp/loot/bob/diary.txt") == nil)
  test("...but does take alice's own", raw("/tmp/loot/alice/own.txt") == "mine")
  securefs.copy("/etc", "/home/alice/etc", aliceS)
  test("cp /etc does not take the shadow file", raw("/home/alice/etc/users.dat") == nil)
  test("cp /etc does not take trust.dat", raw("/home/alice/etc/trust.dat") == nil)
  test("cp /etc still copies what alice may read", raw("/home/alice/etc/motd") == "hi")
  local before = created
  local okRoot = securefs.copy("/", "/home/alice/everything", aliceS)
  test("cp / into a subdirectory is refused, not recursed", okRoot == false)
  test("...and wrote nothing", created == before)
  test("kernel.fs refuses / into itself as well", fs.copyRecursive("/", "/tmp/all") == false)
  test("cp of alice's own tree still works",
    securefs.copy("/home/alice/etc", "/home/alice/etc2", aliceS)
    and raw("/home/alice/etc2/motd") == "hi")
end

print()
print("-- 5. secrets at rest are not world-readable --")
for _, p in ipairs({
  "/etc/trust.dat", "/etc/elevate.dat", "/etc/entropy", "/etc/cluster-manager.cfg",
  "/var/log/kernel.log", "/var/crash/crash-1.txt", "/var/swap/k1",
  "/var/pkg/secrets/mail", "/etc/users.dat.tos-tmp", "/etc/trust.dat.tos-tmp",
}) do
  test("USER cannot read " .. p, not users.canAccessAs(aliceS, p, "r"))
  test("GUEST cannot read " .. p, not users.canAccessAs(guestS, p, "r"))
  test("ADMIN can read " .. p, (users.canAccessAs(adamS, p, "r")))
end
test("end to end: cat /etc/trust.dat as alice", envR.fs.readFile("/etc/trust.dat") == nil)
test("end to end: cat the kernel log as alice", envR.fs.readFile("/var/log/kernel.log") == nil)
for _, p in ipairs({ "/etc/motd", "/etc/tos.cfg", "/etc/hostname", "/etc/keys.cfg",
    "/tos/kernel/init.lua", "/var/pkg/installed/mail/package.lua", "/usr/man/ls.man" }) do
  test("USER still reads " .. p, (users.canAccessAs(aliceS, p, "r")))
end

print()
print("-- 6. accounts: nobody changes an account that outranks them --")
do
  CURRENT = users.sessionFor("adam")
  test("admin cannot reset root's password",
    not users.changePassword("adam", "root", nil, "takeover1"))
  test("admin cannot reset a root-tier account's password",
    not users.changePassword("adam", "rooty", nil, "takeover1"))
  test("admin cannot lock root", not users.setLocked("adam", "root", true))
  test("admin cannot demote a root-tier account", not users.setTier("adam", "rooty", T.USER))
  test("admin cannot delete a root-tier account", not users.delete("adam", "rooty"))
  test("admin still resets a USER's password", (users.changePassword("adam", "bob", nil, "bobnew12")))
  test("admin still locks a USER", (users.setLocked("adam", "bob", true)))
  test("admin still unlocks a USER", (users.setLocked("adam", "bob", false)))
  CURRENT = users.sessionFor("root")
  test("root still resets a root-tier password", (users.changePassword("root", "rooty", nil, "rootypw2")))
  test("create refuses a tier that is not a tier",
    not users.create("root", "weird", "weirdpw1", 99))
  test("setTier refuses a tier that is not a tier", not users.setTier("root", "bob", 7))
  test("root still creates an admin", (users.create("root", "dave", "davepw12", T.ADMIN)))
end

print()
print("-- 7. the login principal manages no one but itself --")
do
  CURRENT = users.loginSession(1)
  test("cannot create an account (naming root as creator)",
    not users.create("root", "mallory", "mallory1", T.ROOT))
  test("...and none was created", users.getUser("mallory") == nil)
  test("cannot reset someone else's password",
    not users.changePassword("root", "bob", nil, "hacked123"))
  test("cannot set a tier", not users.setTier("root", "bob", T.ROOT))
  test("cannot lock an account", not users.setLocked("root", "bob", true))
  test("cannot delete an account", not users.delete("root", "carol"))
  test("CAN change its own password with the old one (first boot)",
    (users.changePassword("carol", "carol", "carolpw1", "carolpw2")))
  CURRENT = nil
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
