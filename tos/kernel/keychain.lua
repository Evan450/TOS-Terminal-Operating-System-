-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Keychain               ║
-- ║  Per-user passphrase stash           ║
-- ╚══════════════════════════════════════╝
-- The vault subsystem (FEAT-10) and any future encrypted-file features
-- need passphrases. Asking the user to retype them on every operation
-- is bad UX; storing them in plaintext on disk is bad security. The
-- keychain compromises:
--
--   * On disk: per-user encrypted blob (vault format) at
--     ~/.keychain.vault. The blob's master passphrase is the user's
--     LOGIN password — derived via crypto.hashPassword so the disk
--     bytes alone can't be used to recover the master.
--   * In memory: an unlocked map { name -> passphrase } scoped to the
--     current session (cleared on logout via users.logout). Lookups
--     are constant-time string compare on the name only.
--   * No persistent in-memory cache: when the user's session
--     disappears the unlocked map is GC'd along with it.
--
-- API:
--   keychain.unlock(masterPass)            decrypt the on-disk vault
--                                          into the in-memory map
--   keychain.lock()                        zero the in-memory map
--   keychain.set(name, passphrase)         add/replace a slot, persist
--   keychain.get(name)                     return passphrase or nil
--   keychain.list()                        slot names (no passphrases)
--   keychain.remove(name)                  delete a slot, persist
--
-- The "master password = login password" choice is deliberate:
--   * One password to remember (the login one).
--   * Changing the login password re-keys the vault automatically
--     (users.changePassword fires keychain.rekey if loaded).
--   * After logout the in-memory map is unreachable; a fresh login
--     re-unlocks from disk.

local keychain = {}

local vault     = nil
local securefs  = nil
local usermod   = nil
local serialize = nil
local log       = nil

-- Per-session unlocked map. Weakly keyed by session token so the
-- entry GCs when the session is reclaimed; logout clears it
-- explicitly too via the users module hook.
local unlocked = setmetatable({}, { __mode = "k" })

function keychain.init(modules)
  vault     = modules.vault     or require("kernel.vault")
  securefs  = modules.securefs
  usermod   = modules.users
  serialize = modules.serialize or require("kernel.serialize")
  log       = modules.log
end

-- ============================================================
-- Path resolution
-- ============================================================

local function keychainPathFor(session)
  if not session or session.isKernel or session.isLogin then return nil end
  if not session.home or session.home == "" or session.home == "/" then return nil end
  return session.home .. "/.keychain.vault"
end

-- ============================================================
-- Disk I/O (vault-encrypted slot table)
-- ============================================================

local function loadDisk(session, masterPass)
  local path = keychainPathFor(session)
  if not path or not securefs or not securefs.exists(path, session) then
    return {}  -- no keychain yet
  end
  local blob = securefs.readFile(path, session)
  if not blob or #blob == 0 then return {} end
  if not vault.isEncrypted(blob) then
    -- File corrupted or partially overwritten — refuse to use it
    -- rather than risk overwriting a recoverable blob.
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
  -- #SEC CR-7 — the keychain stores the user's login password and other
  -- secrets, so it must fail closed rather than persist them under the
  -- XOR fallback. requireStrong makes vault.encrypt refuse when no data
  -- card is present.
  local blob, info = vault.encrypt(encoded, masterPass, { requireStrong = true })
  if not blob then return false, "encrypt failed: " .. tostring(info) end
  return securefs.writeFile(path, blob, session)
end

-- ============================================================
-- Public API
-- ============================================================

--- Unlock the keychain for the current session. `masterPass` is
--- typically the user's login password. Returns (true) on success,
--- (false, err) otherwise.
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

--- Clear the unlocked map for `session`.
function keychain.lock(session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return end
  if unlocked[session] then
    -- Overwrite slot values before dropping the table so the bytes
    -- don't sit in the next allocation cycle's heap.
    local rec = unlocked[session]
    if rec.slots then
      for k in pairs(rec.slots) do rec.slots[k] = nil end
    end
    rec.master = nil
    unlocked[session] = nil
  end
  if log then log.info("keychain", "Locked for " .. session.user) end
end

--- Returns true iff the keychain is currently unlocked for the
--- given (or current) session.
function keychain.isUnlocked(session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false end
  return unlocked[session] ~= nil
end

local function requireUnlocked(session)
  if not unlocked[session] then return nil, "keychain locked" end
  return unlocked[session]
end

--- Set a slot. `name` is a short identifier ("home-tape", "work-floppy").
--- `passphrase` is the secret to stash. Both must be strings.
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

--- Retrieve a slot. Returns the passphrase or (nil, "no such slot").
function keychain.get(name, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return nil, "no session" end
  local rec, err = requireUnlocked(session)
  if not rec then return nil, err end
  return rec.slots[name], rec.slots[name] and nil or "no such slot"
end

--- Remove a slot.
function keychain.remove(name, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false, "no session" end
  local rec, err = requireUnlocked(session)
  if not rec then return false, err end
  rec.slots[name] = nil
  return saveDisk(session, rec.slots, rec.master)
end

--- List slot names (no passphrases).
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

--- Re-key: decrypt with old master, re-encrypt with new master. Used
--- by users.changePassword so the keychain stays usable after the
--- login password rotates.
function keychain.rekey(oldMaster, newMaster, session)
  session = session or (usermod and usermod.currentSession()) or nil
  if not session then return false, "no session" end
  local slots, err = loadDisk(session, oldMaster)
  if not slots then return false, "rekey: " .. tostring(err) end
  -- Update the in-memory record too if currently unlocked.
  if unlocked[session] then
    unlocked[session].master = newMaster
  end
  return saveDisk(session, slots, newMaster)
end

return keychain
