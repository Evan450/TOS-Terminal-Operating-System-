local keychain = {}

local vault     = nil
local securefs  = nil
local usermod   = nil
local serialize = nil
local log       = nil

local unlocked = setmetatable({}, { __mode = "k" })

function keychain.init(modules)
  vault     = modules.vault     or require("kernel.vault")
  securefs  = modules.securefs
  usermod   = modules.users
  serialize = modules.serialize or require("kernel.serialize")
  log       = modules.log
end

local function keychainPathFor(session)
  if not session or session.isKernel or session.isLogin then return nil end
  if not session.home or session.home == "" or session.home == "/" then return nil end
  return session.home .. "/.keychain.vault"
end

local function loadDisk(session, masterPass)
  local path = keychainPathFor(session)
  if not path or not securefs or not securefs.exists(path, session) then
    return {}
  end
  local blob = securefs.readFile(path, session)
  if not blob or #blob == 0 then return {} end
  if not vault.isEncrypted(blob) then

    if log then log.warn("keychain", "On-disk vault for " .. session.user ..
      " is malformed; ignoring") end
    return nil, "keychain file malformed"
  end
  local plain, err = vault.decrypt(blob, masterPass)
  if not plain then return nil, err end
  local ok, data = pcall(serialize.decode, plain, { maxBytes = 65536 })
  if not ok or type(data) ~= "table" then
    return nil, "keychain decoded but isn't a table"
  end
  return data
end

local function saveDisk(session, slotsTable, masterPass)
  local path = keychainPathFor(session)
  if not path or not securefs then return false, "no path" end
  local encoded = serialize.encode(slotsTable)
  if #encoded > 32768 then
    return false, "keychain too large (max 32 KB)"
  end

  local blob, info = vault.encrypt(encoded, masterPass, { requireStrong = true })
  if not blob then return false, "encrypt failed: " .. tostring(info) end

  return (securefs.writeFileAtomic or securefs.writeFile)(path, blob, session)
end

function keychain.unlock(masterPass, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false, "no session" end
  if not vault or not securefs then return false, "keychain not initialized" end
  local slots, err = loadDisk(session, masterPass)
  if not slots then return false, err end
  unlocked[session] = {
    master = masterPass,
    slots  = slots,
  }
  if log then log.info("keychain", "Unlocked for " .. session.user) end
  return true
end

function keychain.lock(session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return end
  if unlocked[session] then

    local rec = unlocked[session]
    if rec.slots then
      for k in pairs(rec.slots) do rec.slots[k] = nil end
    end
    rec.master = nil
    unlocked[session] = nil
  end
  if log then log.info("keychain", "Locked for " .. session.user) end
end

function keychain.isUnlocked(session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false end
  return unlocked[session] ~= nil
end

local function requireUnlocked(session)
  if not unlocked[session] then return nil, "keychain locked" end
  return unlocked[session]
end

function keychain.set(name, passphrase, session)
  if type(name) ~= "string" or type(passphrase) ~= "string" then
    return false, "name and passphrase must be strings"
  end
  if not name:match("^[%w_%-%.]+$") or #name > 64 then
    return false, "name must be alphanum/_/-/. and <= 64 chars"
  end
  if #passphrase > 1024 then return false, "passphrase too long" end
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false, "no session" end
  local rec, err = requireUnlocked(session)
  if not rec then return false, err end

  local prev = rec.slots[name]
  rec.slots[name] = passphrase
  local ok, sErr = saveDisk(session, rec.slots, rec.master)
  if not ok then rec.slots[name] = prev; return false, sErr end
  if log then log.info("keychain", "Set slot '" .. name .. "' for " .. session.user) end
  return true
end

function keychain.get(name, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return nil, "no session" end
  local rec, err = requireUnlocked(session)
  if not rec then return nil, err end
  return rec.slots[name], rec.slots[name] and nil or "no such slot"
end

function keychain.remove(name, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false, "no session" end
  local rec, err = requireUnlocked(session)
  if not rec then return false, err end
  local prev = rec.slots[name]
  rec.slots[name] = nil
  local ok, sErr = saveDisk(session, rec.slots, rec.master)
  if not ok then rec.slots[name] = prev; return false, sErr end
  return true
end

function keychain.list(session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return {} end
  local rec = unlocked[session]
  if not rec then return {} end
  local out = {}
  for k in pairs(rec.slots) do out[#out + 1] = k end
  table.sort(out)
  return out
end

--!
--! Three things the first version got wrong, all of which matter now that
--! it has a caller:
--!   * No vault on disk is NOT a failure and creates nothing. loadDisk
--!     answers {} for "no file", and saving that minted an empty vault for
--!     every user who had never touched the keychain -- or failed outright
--!     on a box with no data card (requireStrong), failing their passwd.
--!   * The in-memory master moved BEFORE the save, so a failed save left an
--!     unlocked keychain whose next `set` wrote under the new password over
--!     a vault the disk still had under the old one.
--!   * Only the session passed in was updated. The caller's session is not
--!     the one that ran `keychain unlock` (that is the seat's shell), and an
--!     unlocked copy still holding the OLD master re-encrypts the vault back
--!     under it at its next `set`. Every unlocked copy for the user moves.
--! (test_keychain_rekey.lua)
function keychain.rekey(oldMaster, newMaster, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false, "no session" end
  if not vault or not securefs then return false, "keychain not initialized" end
  local path = keychainPathFor(session)
  if not path or not securefs.exists(path, session) then return true end
  local slots, err = loadDisk(session, oldMaster)
  if not slots then return false, "rekey: " .. tostring(err) end
  local ok, sErr = saveDisk(session, slots, newMaster)
  if not ok then return false, "rekey: " .. tostring(sErr) end
  for s, rec in pairs(unlocked) do
    if type(s) == "table" and s.user == session.user then rec.master = newMaster end
  end
  return true
end

return keychain
