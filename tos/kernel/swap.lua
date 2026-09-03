-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Disk Swap              ║
-- ║  Explicit spill-to-disk "slow RAM"   ║
-- ╚══════════════════════════════════════╝
-- OpenComputers does NOT model transparent virtual memory: the Lua heap
-- is host-managed and there's no hook to page it to disk, so we cannot
-- magically extend computer.totalMemory(). What we CAN do is let programs
-- explicitly offload large data they don't need resident, freeing RAM,
-- and page it back on demand. Disk I/O in OC carries a per-tick budget,
-- so this really is "slow RAM" — use it for cold data, not hot loops.
--
-- Two layers:
--   * Store API  — swap.store/fetch/free/has/keys/usage/clear: a
--     key→value blob store backed by /var/swap, size-capped.
--   * Table proxy — swap.table{hot=N}: a table whose entries live on
--     disk with a small in-RAM LRU "hot" cache. Reads/writes feel like a
--     normal table; cold entries are serialized out. Each proxy gets a
--     private namespace, so two proxies (or two programs) never collide.
--
-- Swap is VOLATILE by design — like RAM, it does NOT survive a reboot.
-- swap.init() wipes /var/swap on every boot (also clearing any partial
-- files a crash left behind).

local swap = {}

local fs          = nil
local serialize   = nil
local log         = nil
local config      = nil
local compress    = nil
local useCompress = false   -- true only when a data card can deflate/inflate

local SWAP_DIR        = "/var/swap"
local DEFAULT_MAX_KB  = 4096          -- 4 MB default cap
local DISK_MARGIN     = 65536         -- never swap into the last 64 KB of disk
local LRU_DEFAULT     = 16            -- hot-cache entries per table proxy

local maxBytes   = DEFAULT_MAX_KB * 1024
local entries    = {}   -- key(string) -> { file = path, bytes = n }
local totalBytes = 0
local nextId     = 0
local proxies    = setmetatable({}, { __mode = "k" })  -- proxy -> { keyset }

local function nextFile()
  nextId = nextId + 1
  return SWAP_DIR .. "/s" .. nextId
end

-- ============================================================
-- Init / lifecycle
-- ============================================================

function swap.init(modules)
  modules = modules or {}
  fs        = modules.fs        or fs
  serialize = modules.serialize or require("kernel.serialize")
  log       = modules.log
  config    = modules.config
  compress  = modules.compress or compress
  -- Detection-gated: only compress spilled data if a data card can actually
  -- deflate. Without one, swap stores raw serialized bytes exactly as before.
  useCompress = (compress and compress.available and compress.available()) or false

  if not fs then return false, "fs module required" end

  if config and config.get then
    local m = config.get("swapMaxKB")
    if type(m) == "number" and m > 0 then maxBytes = math.floor(m) * 1024 end
  end

  -- Never let swap fill the filesystem: clamp the cap to free space minus
  -- a margin so the OS always has room to write logs / state.
  if fs.spaceFree then
    local free = (fs.spaceFree(SWAP_DIR) or fs.spaceFree("/") or 0)
    local ceil = free - DISK_MARGIN
    if ceil < 0 then ceil = 0 end
    if maxBytes > ceil then maxBytes = ceil end
  end

  if not fs.exists(SWAP_DIR) then fs.makeDirectory(SWAP_DIR) end
  swap.clear()  -- fresh scratch each boot (also sweeps crash debris)

  if log then
    log.info("swap", "Disk swap ready at " .. SWAP_DIR ..
      " (cap " .. math.floor(maxBytes / 1024) .. " KB" ..
      (useCompress and ", compressed" or "") .. ")")
  end
  return true
end

--- Wipe all swapped data and any orphan files under /var/swap.
function swap.clear()
  if not fs then return end
  if not fs.exists(SWAP_DIR) then
    fs.makeDirectory(SWAP_DIR)
  else
    local list = fs.list(SWAP_DIR) or {}
    for _, n in ipairs(list) do
      local clean = n:gsub("/$", "")
      if clean ~= "" then pcall(fs.remove, SWAP_DIR .. "/" .. clean) end
    end
  end
  entries    = {}
  totalBytes = 0
end

-- ============================================================
-- Store API
-- ============================================================

--- Spill a value to disk under `key`, freeing the caller to drop its RAM
--- reference. Returns (true) or (false, err). Storing nil frees the key.
--- @param key string
--- @param value any (serializable: string/number/boolean/table; functions
---        and userdata are not serializable and are dropped by the encoder)
function swap.store(key, value)
  if not fs then return false, "swap not initialized" end
  if type(key) ~= "string" then return false, "key must be a string" end
  if value == nil then swap.free(key); return true end

  local ok, data = pcall(serialize.encode, value)
  if not ok then return false, "serialize failed: " .. tostring(data) end
  -- Compress the spilled bytes when a data card is present (pack() falls back
  -- to a "stored" frame for tiny/incompressible data). The cap accounts for
  -- the on-disk size, so compression lets more logical data fit under it.
  if useCompress then
    local packed = compress.pack(data)
    if packed then data = packed end
  end
  local n = #data

  local old      = entries[key]
  local oldBytes = old and old.bytes or 0
  if (totalBytes - oldBytes + n) > maxBytes then
    return false, "swap full (cap " .. math.floor(maxBytes / 1024) .. " KB)"
  end

  local file = (old and old.file) or nextFile()
  local wOk, wErr = fs.writeFile(file, data)
  if not wOk then return false, wErr or "write failed" end

  totalBytes  = totalBytes - oldBytes + n
  entries[key] = { file = file, bytes = n }
  return true
end

--- Page a value back into RAM. Returns the value, or nil if not present
--- (or unreadable / undecodable — swap is scratch, so we fail soft).
function swap.fetch(key)
  if not fs then return nil end
  local e = entries[key]
  if not e then return nil end
  local data = fs.readFile(e.file)
  if not data then return nil end
  -- Reverse compression if this entry was packed (all entries within a boot
  -- share useCompress, and swap is wiped each boot, so this is consistent).
  if useCompress and compress and compress.isPacked(data) then
    data = compress.unpack(data)
    if not data then return nil end
  end
  -- Allow values up to the whole cap (well above the default 256 KB).
  local v = serialize.decode(data, { maxBytes = maxBytes + 1024 })
  return v
end

--- Drop a key's on-disk copy. Returns true if it existed.
function swap.free(key)
  local e = entries[key]
  if not e then return false end
  pcall(fs.remove, e.file)
  totalBytes  = totalBytes - e.bytes
  entries[key] = nil
  return true
end

function swap.has(key) return entries[key] ~= nil end

function swap.keys()
  local out = {}
  for k in pairs(entries) do out[#out + 1] = k end
  table.sort(out)
  return out
end

--- { bytes = used, count = entries, max = cap } — for status UIs.
function swap.usage()
  local count = 0
  for _ in pairs(entries) do count = count + 1 end
  return { bytes = totalBytes, count = count, max = maxBytes }
end

-- ============================================================
-- Table proxy — "feels like RAM" disk-backed table
-- ============================================================

local function keyStr(ns, k)
  local t = type(k)
  if t == "number" then return ns .. "n" .. tostring(k) end
  if t == "string" then return ns .. "s" .. k end
  return nil  -- unsupported key type
end

--- Return a disk-backed table. Entries live in swap; a small in-RAM LRU
--- cache (opts.hot, default 16) keeps the working set fast. Writes are
--- write-through (durable in swap immediately), so an LRU eviction only
--- drops the cache copy. Honors #, pairs(), and nil-assignment delete.
--- Free it with swap.freeTable(proxy) when done.
function swap.table(opts)
  opts = opts or {}
  local hotMax = tonumber(opts.hot) or LRU_DEFAULT
  if hotMax < 1 then hotMax = 1 end

  nextId = nextId + 1
  local ns = "t" .. nextId .. ":"

  local hot    = {}   -- keyStr -> value (read/write cache)
  local order  = {}   -- LRU, front = most-recently-used
  local keyset = {}   -- keyStr -> original key (for # and pairs)

  local function untrackOrder(s)
    for i = 1, #order do
      if order[i] == s then table.remove(order, i); return end
    end
  end
  local function touch(s)
    untrackOrder(s)
    table.insert(order, 1, s)
    while #order > hotMax do
      local victim = table.remove(order)
      if victim then hot[victim] = nil end  -- value already in swap
    end
  end

  local proxy = setmetatable({}, {
    __index = function(_, k)
      local s = keyStr(ns, k); if not s then return nil end
      if hot[s] ~= nil then touch(s); return hot[s] end
      local v = swap.fetch(s)
      if v ~= nil then hot[s] = v; touch(s) end
      return v
    end,
    __newindex = function(_, k, v)
      local s = keyStr(ns, k)
      if not s then error("swap.table: unsupported key type " .. type(k), 2) end
      if v == nil then
        swap.free(s); hot[s] = nil; keyset[s] = nil; untrackOrder(s)
        return
      end
      local ok, err = swap.store(s, v)
      if not ok then error("swap.table: " .. tostring(err), 2) end
      keyset[s] = k
      hot[s]    = v
      touch(s)
    end,
    __len = function()
      local n = 0
      for _ in pairs(keyset) do n = n + 1 end
      return n
    end,
    __pairs = function(_)
      -- Snapshot the keyset so the caller can read during iteration.
      local list = {}
      for s, ok in pairs(keyset) do list[#list + 1] = { s = s, k = ok } end
      local i = 0
      return function()
        i = i + 1
        local e = list[i]
        if not e then return nil end
        local v = hot[e.s]
        if v == nil then v = swap.fetch(e.s) end
        return e.k, v
      end
    end,
  })

  proxies[proxy] = { keyset = keyset }
  return proxy
end

--- Release every swap entry owned by a proxy from swap.table().
function swap.freeTable(proxy)
  local info = proxies[proxy]
  if not info then return false, "not a swap table" end
  for s in pairs(info.keyset) do swap.free(s) end
  proxies[proxy] = nil
  return true
end

-- Constants / introspection for callers and tests.
swap.SWAP_DIR = SWAP_DIR

return swap
