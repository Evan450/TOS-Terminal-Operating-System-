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
  return securefs.writeFile(path, blob, session)
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
  rec.slots[name] = passphrase
  local ok, sErr = saveDisk(session, rec.slots, rec.master)
  if not ok then return false, sErr end
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
  rec.slots[name] = nil
  return saveDisk(session, rec.slots, rec.master)
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

function keychain.rekey(oldMaster, newMaster, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false, "no session" end
  local slots, err = loadDisk(session, oldMaster)
  if not slots then return false, "rekey: " .. tostring(err) end

  if unlocked[session] then
    unlocked[session].master = newMaster
  end
  return saveDisk(session, slots, newMaster)
end

return keychain
