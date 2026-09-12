-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Property Test: an ACL answer never depends on how a path is     ║
-- ║  spelled                                                         ║
-- ║                                                                  ║
-- ║  Thousands of hostile spellings -- "..", ".", "//", backslashes, ║
-- ║  trailing slashes, the atomic-save ".tos-tmp" suffix, NUL bytes, ║
-- ║  non-strings -- thrown at the REAL kernel.fs normaliser,         ║
-- ║  kernel.users checkAccess and kernel.securefs guards (Sep 2026   ║
-- ║  pentest: a property pass instead of another read-through).      ║
-- ║  The invariants:                                                 ║
-- ║   1. canAccessAs(s, p) == canAccessAs(s, normalize(p)).          ║
-- ║   2. A USER never reads a secret, however it is spelled.         ║
-- ║   3. Nobody but an armed root writes the kernel or /init.lua.    ║
-- ║   4. A path the normaliser rejects is refused -- never raised,   ║
-- ║      because a raise is a verdict a careless pcall can misread.  ║
-- ║   5. A spelling the disk may fold (case, Kelvin sign, trailing   ║
-- ║      dot) never gets more than the path it folds to: OC's disk   ║
-- ║      is case-insensitive on a Windows or macOS host.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_path_acl_properties.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }

local fs = require("kernel.fs")
local users = require("kernel.users")
-- checkAccess reads its normaliser from the fs it was initialised with.
-- No DB on disk, so first boot mints root in memory; nothing is written.
users.init({ fs = { normalize = fs.normalize, exists = function() return false end,
  readFile = function() return nil end, writeFile = function() return true end,
  makeDirectory = function() return true end },
  crypto = { init = function() end, hasHardware = function() return false end,
    salt = function(n) return string.rep("s", n or 16) end,
    hashPassword = function(pw, s) return "h:" .. pw .. s end } })
local securefs = require("kernel.securefs")
securefs.init({ fs = fs, users = users, log = nil })

local T = users.TIER
local alice = { user = "alice", tier = T.USER, home = "/home/alice" }
local adam  = { user = "adam",  tier = T.ADMIN, home = "/home/adam" }

local SEGS = { "..", ".", "", "etc", "users.dat", "trust.dat", "elevate.dat", "home", "alice",
  "bob", "tos", "kernel", "init.lua", "var", "log", "kernel.log", "tmp", "usr", "lib",
  "users.dat.tos-tmp", "x" }
local SEPS = { "/", "//", "\\", "/./", "/../" }
local seed = 4242
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
local function randomPath()
  local parts = { (rnd(4) == 0) and "" or "/" }
  for _ = 1, rnd(7) + 1 do
    parts[#parts + 1] = SEGS[rnd(#SEGS) + 1]
    parts[#parts + 1] = SEPS[rnd(#SEPS) + 1]
  end
  if rnd(3) == 0 then parts[#parts] = "" end
  return table.concat(parts)
end

local SECRETS = { ["/etc/users.dat"] = true, ["/etc/trust.dat"] = true, ["/etc/elevate.dat"] = true,
  ["/var/log/kernel.log"] = true, ["/etc/users.dat.tos-tmp"] = true }
local function kernelPath(n) return n == "/init.lua" or n == "/tos" or (n and n:sub(1, 5) == "/tos/") end

print("=== path/ACL properties over 4000 spellings ===")
print()
local spellingDiffers, secretLeaks, kernelWrites, raised = 0, 0, 0, 0
local examples = {}
local function note(kind, p) if not examples[kind] then examples[kind] = p end end
for _ = 1, 4000 do
  local p = randomPath()
  local n = fs.normalize(p)
  for _, s in ipairs({ alice, adam }) do
    for _, mode in ipairs({ "r", "w" }) do
      local okA, a = pcall(users.canAccessAs, s, p, mode)
      local okB, b = pcall(users.canAccessAs, s, n, mode)
      if not okA or not okB then raised = raised + 1; note("raise", p)
      elseif (a and true or false) ~= (b and true or false) then spellingDiffers = spellingDiffers + 1; note("spelling", p) end
    end
  end
  if n and SECRETS[n] then
    local okR, allowed = pcall(users.canAccessAs, alice, p, "r")
    if okR and allowed then secretLeaks = secretLeaks + 1; note("secret", p) end
  end
  if kernelPath(n) then
    for _, s in ipairs({ alice, adam }) do
      local okW, allowedW = pcall(securefs.writeFile, p, "x", s)
      if okW and allowedW then kernelWrites = kernelWrites + 1; note("kernel", p) end
    end
  end
end
test("1. the ACL answer never depends on the spelling" .. (examples.spelling and ("  e.g. " .. examples.spelling) or ""),
  spellingDiffers == 0)
test("2. a USER never reads a secret, however spelled" .. (examples.secret and ("  e.g. " .. examples.secret) or ""),
  secretLeaks == 0)
test("3. no USER or ADMIN writes the kernel or /init.lua" .. (examples.kernel and ("  e.g. " .. examples.kernel) or ""),
  kernelWrites == 0)
test("   (the check never raised on a generated path)" .. (examples.raise and ("  e.g. " .. examples.raise) or ""),
  raised == 0)

print()
print("-- 4. what the normaliser rejects is refused, not raised --")
for _, bad in ipairs({ "/etc/users.dat\0", "\0", 42, {}, true }) do
  local label = type(bad) == "string" and (bad:gsub("%z", "\\0")) or type(bad)
  local okC, verdict = pcall(users.canAccessAs, alice, bad, "r")
  test("canAccessAs(" .. label .. ") returns a refusal", okC and not verdict)
  local okS, v2 = pcall(securefs.readFile, bad, alice)
  test("securefs.readFile(" .. label .. ") returns a refusal", okS and v2 == nil)
end

print()
print("-- 5. a spelling the disk may fold never gets more than the path it folds to --")
-- OpenComputers' buffered filesystem folds case on a Windows or macOS host
-- (Java's toLowerCase, which also sends the Kelvin sign to "k"), and a
-- Windows host drops a trailing dot or space. Each variant may BE the file.
local CANON = { "/etc/users.dat", "/etc/trust.dat", "/etc/elevate.dat", "/var/log/kernel.log",
  "/var/pkg/secrets/key", "/var/mail/bob", "/home/bob/notes", "/root/x", "/etc/users.dat.tos-tmp",
  "/tos/kernel/init.lua", "/init.lua", "/etc/passwd" }
local function variants(c)
  local out = { c:upper(), (c:gsub("^/(%a)", function(a) return "/" .. a:upper() end)) }
  out[#out + 1] = (c:gsub("%a", function(a) return (rnd(2) == 0) and a:upper() or a end))
  if c:find("k", 1, true) then out[#out + 1] = (c:gsub("k", "\226\132\170")) end
  out[#out + 1] = (c:gsub("/([^/]+)", "/%1.", 1))       -- the first segment gains a dot
  out[#out + 1] = c .. "."
  out[#out + 1] = c .. " "
  return out
end
local wider, protectedMiss, wEx, pEx = 0, 0, nil, nil
for _, c in ipairs(CANON) do
  for _, v in ipairs(variants(c)) do
    for _, s in ipairs({ alice, adam }) do
      for _, mode in ipairs({ "r", "w" }) do
        if users.canAccessAs(s, v, mode) and not users.canAccessAs(s, c, mode) then
          wider = wider + 1
          wEx = wEx or (s.user .. " " .. mode .. " " .. (v:gsub("[\128-\255]+", "<K>")))
        end
      end
    end
    if securefs._isProtectedTarget(c, adam) and not securefs._isProtectedTarget(v, adam) then
      protectedMiss = protectedMiss + 1; pEx = pEx or v
    end
  end
end
test("no folded spelling reads or writes more than its path" .. (wEx and ("  e.g. " .. wEx) or ""),
  wider == 0)
test("a folded spelling of a protected path is still protected" .. (pEx and ("  e.g. " .. pEx) or ""),
  protectedMiss == 0)
test("an ordinary mixed-case name in your own home still works",
  users.canAccessAs(alice, "/home/alice/Notes.TXT", "w") and users.canAccessAs(alice, "/home/alice/a.", "r"))
local carol = { user = "Carol", tier = T.USER, home = "/home/Carol" }
test("a mixed-case account still owns its home", users.canAccessAs(carol, "/home/Carol/x", "w"))
test("...and not another's", not users.canAccessAs(carol, "/home/alice/x", "r"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
