-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Trash / Undelete       ║
-- ╚══════════════════════════════════════╝
-- Soft-delete layer. `rm` and related commands move files into the
-- user's trash directory instead of unlinking them, so a fat-fingered
-- delete can be reversed with `restore`. The trash dir is per-user
-- (lives under the user's home as `~/.trash/`) so a USER-tier delete
-- can't enumerate or recover another user's deleted files.
--
-- Design notes:
--   * Storage is per-user. /root/.trash, /home/<user>/.trash. Guest
--     deletes still bypass the trash (no home to put it in) and go
--     straight through.
--   * Each trashed entry is given a unique name: <basename>~<epoch>
--     so two `rm /foo` calls in a row don't clobber each other.
--   * A metadata sidecar (`.trashmeta`) records the original path,
--     deletion timestamp, and original mode, so `restore` knows where
--     to put it back. The metadata file is itself a serialize.encode
--     table.
--   * Hard cap on trash size and entry count to prevent a runaway
--     `rm -rf` from filling the disk with "deleted" files that are
--     still on disk. Oldest entries auto-purged when caps exceeded.
--   * Trashing is opt-in per remove: `rm` calls trash.put before
--     securefs.remove; commands that explicitly want hard-delete
--     (shred, secure-delete, system cleanup) call securefs.remove
--     directly.

local trash = {}

-- Module refs (set during init)
local securefs = nil
local fs = nil  -- raw kernel.fs for the trash dir itself (we own that path)
local usersmod = nil
local log = nil
local serialize = nil

-- Configuration (overridable from /etc/tos.cfg via init opts)
local MAX_TRASH_BYTES = 4 * 1024 * 1024   -- 4 MB per user
local MAX_TRASH_ITEMS = 256
local META_SUFFIX     = ".trashmeta"

function trash.init(modules)
  securefs  = modules.securefs
  fs        = modules.fs
  usersmod  = modules.users
  log       = modules.log
  serialize = modules.serialize or require("kernel.serialize")

  if modules.config and modules.config.get then
    local mb = modules.config.get("trashMaxMB")
    if type(mb) == "number" and mb > 0 then
      MAX_TRASH_BYTES = math.floor(mb * 1024 * 1024)
    end
    local mi = modules.config.get("trashMaxItems")
    if type(mi) == "number" and mi > 0 then
      MAX_TRASH_ITEMS = math.floor(mi)
    end
  end
end

-- ============================================================
-- Per-user trash directory resolution
-- ============================================================

local function trashDirFor(session)
  if not session then return nil end
  -- Guest gets no trash (no persistent home), and the kernel pseudo-
  -- session shouldn't trash either.
  if session.isKernel or session.isGuest or session.user == "guest" then
    return nil
  end
  local home = session.home
  if type(home) ~= "string" or home == "" or home == "/" then
    return nil
  end
  return home .. "/.trash"
end

local function ensureTrashDir(session)
  local dir = trashDirFor(session)
  if not dir or not securefs then return nil end
  if not securefs.exists(dir, session) then
    -- The trash dir's parent (the user's home) is already writable to
    -- them; making .trash inside it just inherits that ACL.
    securefs.makeDirectory(dir, session)
  end
  return dir
end

-- ============================================================
-- Size + entry-count enforcement
-- ============================================================

local function listTrashEntries(dir, session)
  local items = securefs.list(dir, session)
  if type(items) ~= "table" then return {} end
  local entries = {}
  for _, name in ipairs(items) do
    local clean = name:gsub("/$", "")
    if not clean:find(META_SUFFIX, 1, true) then
      -- Pair entry with its meta file
      local entry = { name = clean, path = dir .. "/" .. clean }
      local metaPath = entry.path .. META_SUFFIX
      if securefs.exists(metaPath, session) then
        local raw = securefs.readFile(metaPath, session)
        if raw then
          local ok, meta = pcall(serialize.decode, raw, { maxBytes = 4096 })
          if ok and type(meta) == "table" then
            entry.meta = meta
          end
        end
      end
      entry.size = securefs.size(entry.path, session) or 0
      entries[#entries + 1] = entry
    end
  end
  return entries
end

local function purgeOldest(dir, session, needBytes, needSlots)
  local entries = listTrashEntries(dir, session)
  -- Sort by deletion time ascending (oldest first); fall back to name.
  table.sort(entries, function(a, b)
    local ta = a.meta and a.meta.deletedAt or 0
    local tb = b.meta and b.meta.deletedAt or 0
    if ta == tb then return a.name < b.name end
    return ta < tb
  end)
  local totalBytes = 0
  for _, e in ipairs(entries) do totalBytes = totalBytes + e.size end
  local count = #entries

  for _, e in ipairs(entries) do
    if (needBytes <= 0 and needSlots <= 0)
       and totalBytes <= MAX_TRASH_BYTES
       and count <= MAX_TRASH_ITEMS then
      break
    end
    -- Remove the entry and its sidecar.
    securefs.remove(e.path .. META_SUFFIX, session)
    securefs.remove(e.path, session)
    totalBytes = totalBytes - e.size
    count = count - 1
    needBytes = needBytes - e.size
    needSlots = needSlots - 1
    if log then
      log.info("trash", "Auto-purged: " .. (e.meta and e.meta.origin or e.name))
    end
  end
end

-- ============================================================
-- Public API
-- ============================================================

--- Move a file (or directory) into the caller's trash. Returns
--- (true, trashEntryPath) on success, (false, reason) otherwise.
--- The session arg drives both the trash location and the ACL check
--- on the source path.
function trash.put(srcPath, session)
  if not securefs then return false, "trash not initialized" end
  session = session or (usersmod and usersmod.currentSession()) or nil
  if not session then return false, "no session" end

  local dir = ensureTrashDir(session)
  if not dir then
    -- No trash for this principal (guest/kernel) — caller should hard-delete.
    return false, "no trash for this session"
  end

  -- Source must exist and the caller must have read+write on it (a
  -- delete is conceptually a "move out", which both reads and writes).
  local norm = securefs.normalize(srcPath)
  if not securefs.exists(norm, session) then
    return false, "source not found: " .. norm
  end

  -- Compute the trashed name. Collisions resolved by appending
  -- "~N" until we find a free slot.
  local function baseName(p) return p:match("([^/]+)/?$") or "unnamed" end
  local base = baseName(norm)
  local now = (os.time and os.time()) or 0
  local trashName = base .. "~" .. tostring(now)
  local candidate = dir .. "/" .. trashName
  local n = 1
  while securefs.exists(candidate, session) do
    candidate = dir .. "/" .. trashName .. "~" .. n
    n = n + 1
  end

  -- Pre-purge if we'd push past the caps. Read source size for budgeting.
  local srcSize = securefs.size(norm, session) or 0
  if srcSize > MAX_TRASH_BYTES then
    -- A single file too big to fit. Refuse to trash; caller can hard-delete
    -- if they really want it gone.
    return false, "file too large for trash (" .. srcSize .. " > " .. MAX_TRASH_BYTES .. ")"
  end
  purgeOldest(dir, session, srcSize, 1)

  -- Move via rename when possible (same FS), copy+remove otherwise.
  local ok, err = securefs.rename(norm, candidate, session)
  if not ok then
    -- rename across filesystems would fail; try copy+remove.
    ok, err = securefs.copy(norm, candidate, session)
    if ok then
      securefs.remove(norm, session)
    else
      return false, "trash move failed: " .. tostring(err)
    end
  end

  -- Sidecar metadata.
  local meta = {
    origin    = norm,
    deletedAt = now,
    deletedBy = session.user,
    size      = srcSize,
  }
  local mOk, mErr = securefs.writeFile(candidate .. META_SUFFIX,
    serialize.encode(meta), session)
  if not mOk and log then
    log.warn("trash", "Couldn't write metadata for " .. candidate .. ": " ..
      tostring(mErr))
  end
  if log then
    log.info("trash", "Trashed " .. norm .. " -> " .. candidate)
  end
  return true, candidate
end

--- List the caller's trash entries. Returns an array of
--- { name, path, size, origin, deletedAt } records sorted newest-first.
function trash.list(session)
  if not securefs then return {}, "trash not initialized" end
  session = session or (usersmod and usersmod.currentSession()) or nil
  if not session then return {}, "no session" end
  local dir = trashDirFor(session)
  if not dir or not securefs.exists(dir, session) then return {} end
  local entries = listTrashEntries(dir, session)
  table.sort(entries, function(a, b)
    local ta = a.meta and a.meta.deletedAt or 0
    local tb = b.meta and b.meta.deletedAt or 0
    return ta > tb
  end)
  local out = {}
  for i, e in ipairs(entries) do
    out[i] = {
      name      = e.name,
      path      = e.path,
      size      = e.size,
      origin    = e.meta and e.meta.origin    or "?",
      deletedAt = e.meta and e.meta.deletedAt or 0,
      deletedBy = e.meta and e.meta.deletedBy or "?",
    }
  end
  return out
end

--- Restore a trash entry by its name back to its original path (or
--- to `destOverride` if supplied). Returns (true) on success, (false,
--- reason) otherwise. Refuses to overwrite an existing file unless
--- the caller passes `force = true` in opts.
function trash.restore(name, opts)
  if not securefs then return false, "trash not initialized" end
  opts = opts or {}
  local session = opts.session or (usersmod and usersmod.currentSession()) or nil
  if not session then return false, "no session" end
  local dir = trashDirFor(session)
  if not dir then return false, "no trash for this session" end

  local srcPath = dir .. "/" .. name
  local metaPath = srcPath .. META_SUFFIX
  if not securefs.exists(srcPath, session) then
    return false, "no such trash entry: " .. name
  end

  local origin = opts.dest
  if not origin then
    if not securefs.exists(metaPath, session) then
      return false, "metadata missing for " .. name ..
        " — pass an explicit dest to restore"
    end
    local raw = securefs.readFile(metaPath, session)
    local ok, meta = pcall(serialize.decode, raw, { maxBytes = 4096 })
    if not ok or type(meta) ~= "table" or type(meta.origin) ~= "string" then
      return false, "metadata corrupt for " .. name
    end
    origin = meta.origin
  end
  origin = securefs.normalize(origin)

  -- Don't silently overwrite the live filesystem.
  if securefs.exists(origin, session) and not opts.force then
    return false, "destination exists; pass force=true to overwrite: " .. origin
  end

  -- Move back (rename, fallback to copy+remove).
  local ok, err = securefs.rename(srcPath, origin, session)
  if not ok then
    ok, err = securefs.copy(srcPath, origin, session)
    if ok then
      securefs.remove(srcPath, session)
    else
      return false, "restore failed: " .. tostring(err)
    end
  end
  securefs.remove(metaPath, session)
  if log then log.info("trash", "Restored " .. name .. " -> " .. origin) end
  return true, origin
end

--- Permanently empty the caller's trash.
function trash.empty(session)
  if not securefs then return false, "trash not initialized" end
  session = session or (usersmod and usersmod.currentSession()) or nil
  if not session then return false, "no session" end
  local dir = trashDirFor(session)
  if not dir or not securefs.exists(dir, session) then return true, 0 end
  local entries = listTrashEntries(dir, session)
  local removed = 0
  for _, e in ipairs(entries) do
    securefs.remove(e.path .. META_SUFFIX, session)
    if securefs.remove(e.path, session) then removed = removed + 1 end
  end
  if log then log.info("trash", "Emptied trash (" .. removed .. " items)") end
  return true, removed
end

--- Cap helpers (for `diag` reporting).
function trash.usage(session)
  if not securefs then return nil end
  session = session or (usersmod and usersmod.currentSession()) or nil
  if not session then return nil end
  local dir = trashDirFor(session)
  if not dir or not securefs.exists(dir, session) then
    return { count = 0, bytes = 0, max_count = MAX_TRASH_ITEMS, max_bytes = MAX_TRASH_BYTES }
  end
  local entries = listTrashEntries(dir, session)
  local bytes = 0
  for _, e in ipairs(entries) do bytes = bytes + e.size end
  return {
    count     = #entries,
    bytes     = bytes,
    max_count = MAX_TRASH_ITEMS,
    max_bytes = MAX_TRASH_BYTES,
  }
end

-- #MEM — lazy self-initialization. The kernel no longer initializes trash
-- at boot; the CLI shell's `rm`/`trash` path require()s this module
-- directly, and the panels shell reaches it through the _TOS.trash lazy
-- slot. Both routes converge here: on load, pull deps from the live _TOS
-- handles. Off-box tests (no _TOS.securefs) still use explicit init().
do
  local T = rawget(_G, "_TOS")
  if T and T.securefs and not securefs then
    pcall(trash.init, {
      securefs  = T.securefs,
      fs        = T.fs,
      users     = T.users,
      log       = T.logObj,
      serialize = serialize,
      config    = T.config,
    })
  end
end

return trash
