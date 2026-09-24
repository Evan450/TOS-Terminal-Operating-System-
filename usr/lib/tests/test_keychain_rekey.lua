-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the keychain follows a password change        ║
-- ║                                                                ║
-- ║  AUDIT 5: "CHANGING A LOGIN PASSWORD ORPHANS THE KEYCHAIN,      ║
-- ║  PERMANENTLY." The keychain's master is the login password and  ║
-- ║  keychain.rekey existed, but nothing called it: the vault stayed ║
-- ║  under the old password and the next unlock lost every slot.    ║
-- ║  The audit named what had to be settled first, and each is      ║
-- ║  pinned here:                                                   ║
-- ║   * a user with no vault gets no vault, and passwd cannot fail  ║
-- ║     over a keychain they never used;                            ║
-- ║   * a rekey that fails leaves the vault openable with the OLD   ║
-- ║     password and says so -- it never fails passwd;              ║
-- ║   * an admin reset cannot re-key, and says so.                  ║
-- ║  Plus: an unlocked copy in ANOTHER session (the seat's shell)   ║
-- ║  moves to the new master too, or its next `set` would re-       ║
-- ║  encrypt the vault under the old one; and a refused save no     ║
-- ║  longer leaves a slot in memory that the disk does not have.    ║
-- ║                                                                ║
-- ║  Drives the REAL kernel.users, securefs, fs and keychain over   ║
-- ║  an in-memory disk. Only the cipher is a stand-in (the real one ║
-- ║  refuses to run without a data card, by design).                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_keychain_rekey.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end }
local CURRENT = nil
package.loaded["kernel.process"] = {
  currentSession = function() return CURRENT end,
  currentToken = function() return nil end,
  yieldCooperative = function() end,
}
local crypto = {
  init = function() end,
  salt = function() return "SALT" end,
  hashPassword = function(pw, salt) return "H:" .. tostring(salt) .. "|" .. tostring(pw) end,
  verifyPassword = function(pw, salt, hash)
    return hash == "H:" .. tostring(salt) .. "|" .. tostring(pw), false
  end,
  token = (function() local n = 0; return function() n = n + 1; return "tok" .. n end end)(),
  hasHardware = function() return false end,
}
package.loaded["kernel.crypto"] = crypto

-- ── In-memory disk (the managed-filesystem shape kernel.fs drives) ──
local files, dirs, handles, nextH = {}, { ["/"] = true }, {}, 1
local failWrites = false
local disk = { address = "disk0" }
function disk.exists(p) return files[p] ~= nil or dirs[p] == true end
function disk.isDirectory(p) return dirs[p] == true end
function disk.makeDirectory(p) dirs[p] = true; return true end
function disk.list() return {} end
function disk.size(p) return files[p] and #files[p] or 0 end
function disk.lastModified() return 0 end
function disk.remove(p) files[p] = nil; dirs[p] = nil; return true end
function disk.rename(a, b) files[b] = files[a]; files[a] = nil; return true end
function disk.open(p, mode)
  if mode == "r" and files[p] == nil then return nil, "no such file" end
  if mode == "w" then files[p] = "" end
  local h = nextH; nextH = nextH + 1
  handles[h] = { path = p, pos = 1 }
  return h
end
function disk.write(h, data)
  if failWrites then return nil, "not enough space" end
  local st = handles[h]; files[st.path] = files[st.path] .. data; return true
end
function disk.read(h, n)
  local st = handles[h]; local s = files[st.path] or ""
  if st.pos > #s then return nil end
  local chunk = s:sub(st.pos, st.pos + n - 1); st.pos = st.pos + #chunk
  return chunk
end
function disk.close(h) handles[h] = nil; return true end
function disk.spaceTotal() return 1e6 end
function disk.spaceUsed() return 0 end

local fs = require("kernel.fs")
fs.init(disk)
local users = require("kernel.users")
users.init({ fs = fs, crypto = crypto })
local securefs = require("kernel.securefs")
securefs.init({ fs = fs, users = users })

-- Stand-in cipher: the blob names its password, and decrypt checks it.
local strongOK = true
local vault = {
  isEncrypted = function(b) return type(b) == "string" and b:sub(1, 6) == "VAULT:" end,
  encrypt = function(plain, pass, o)
    if o and o.requireStrong and not strongOK then return nil, "no data card" end
    return "VAULT:" .. pass .. "\0" .. plain
  end,
  decrypt = function(blob, pass)
    local p, plain = blob:match("^VAULT:(.-)%z(.*)$")
    if p ~= pass then return nil, "MAC mismatch" end
    return plain
  end,
}
local keychain = require("kernel.keychain")
keychain.init({ vault = vault, securefs = securefs, users = users })
_G._TOS = { keychain = keychain }

CURRENT = users.kernelSession()
assert(users.changePassword("root", "root", "root", "rootpw12"))
assert(users.create("root", "bob", "bobpass1", 1))
assert(users.create("root", "cat", "catpass1", 1))
assert(users.create("root", "adam", "adampass1", 2))
local VAULT = "/home/bob/.keychain.vault"

print("=== the keychain follows a password change ===")
print()

-- bob's seat shell: logged in, keychain unlocked, one slot stored.
CURRENT = nil
local bobTok = users.login("bob", "bobpass1", { setCurrent = false })
local shellSess = users.getSession(bobTok)
CURRENT = shellSess
assert(keychain.unlock("bobpass1", shellSess))
assert(keychain.set("tape", "s3cret", shellSess))
test("the vault exists after the first set", files[VAULT] ~= nil)

print("-- a self change re-keys --")
do
  local ok, note = users.changePassword("bob", "bob", "bobpass1", "bobpass2")
  test("passwd succeeds", ok == true)
  test("...with nothing to warn about", note == nil)
  local probe = users.sessionFor("bob")
  test("the vault no longer opens with the old password", not keychain.unlock("bobpass1", probe))
  test("it opens with the new one", (keychain.unlock("bobpass2", probe)))
  test("...and the slot survived", keychain.get("tape", probe) == "s3cret")
  keychain.lock(probe)

  -- The shell that unlocked BEFORE the change saves under the new master.
  assert(keychain.set("floppy", "f1", shellSess))
  local probe2 = users.sessionFor("bob")
  test("a set from the already-unlocked shell keeps the NEW master",
    (keychain.unlock("bobpass2", probe2)) and keychain.get("floppy", probe2) == "f1")
  keychain.lock(probe2)
end

print()
print("-- no vault, no vault --")
do
  CURRENT = users.sessionFor("cat")
  local ok, note = users.changePassword("cat", "cat", "catpass1", "catpass2")
  test("a user who never used the keychain changes their password", ok == true and note == nil)
  test("...and gets no vault out of it", files["/home/cat/.keychain.vault"] == nil)
  strongOK = false
  CURRENT = users.sessionFor("cat")
  test("...even on a box with no data card", (users.changePassword("cat", "cat", "catpass2", "catpass3")))
  strongOK = true
end

print()
print("-- a rekey that cannot happen does not cost the vault --")
do
  local before = files[VAULT]
  strongOK = false
  CURRENT = shellSess
  local ok, note = users.changePassword("bob", "bob", "bobpass2", "bobpass3")
  strongOK = true
  test("passwd still succeeds", ok == true)
  test("...and says the keychain kept the OLD password",
    type(note) == "string" and note:find("OLD password", 1, true) ~= nil)
  test("...the vault is byte-for-byte untouched", files[VAULT] == before)
  local probe = users.sessionFor("bob")
  test("...and still opens with the previous password", (keychain.unlock("bobpass2", probe)))
  keychain.lock(probe)
  test("the unlocked shell kept the master that matches the disk", (function()
    assert(keychain.set("x", "y", shellSess))
    local p = users.sessionFor("bob")
    local okU = keychain.unlock("bobpass2", p)
    keychain.lock(p)
    return okU
  end)())
end

print()
print("-- an admin reset cannot re-key, and says so --")
do
  local before = files[VAULT]
  CURRENT = users.sessionFor("adam")
  local ok, note = users.changePassword("adam", "bob", nil, "resetpw1")
  test("the reset succeeds", ok == true)
  test("...with a note naming the OLD password",
    type(note) == "string" and note:find("OLD password", 1, true) ~= nil)
  test("...and the vault is untouched", files[VAULT] == before)
end

print()
print("-- a refused save leaves memory as it was --")
do
  local probe = users.sessionFor("bob")
  assert(keychain.unlock("bobpass2", probe))
  failWrites = true
  test("set reports the failure", not keychain.set("new-slot", "v", probe))
  test("...and the slot is not in memory", keychain.get("new-slot", probe) == nil)
  test("remove reports the failure", not keychain.remove("tape", probe))
  test("...and the slot is still there", keychain.get("tape", probe) == "s3cret")
  failWrites = false
  test("the vault on disk survived both", (function()
    local p = users.sessionFor("bob")
    local okU = keychain.unlock("bobpass2", p)
    local v = keychain.get("tape", p)
    keychain.lock(p)
    return okU and v == "s3cret"
  end)())
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
