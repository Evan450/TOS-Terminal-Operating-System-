local swap = {}

local fs          = nil
local serialize   = nil
local log         = nil
local config      = nil
local compress    = nil
local useCompress = false

local SWAP_DIR        = "/var/swap"
local DEFAULT_MAX_KB  = 4096
local DISK_MARGIN     = 65536
local LRU_DEFAULT     = 16

local maxBytes   = DEFAULT_MAX_KB * 1024
local entries    = {}
local totalBytes = 0
local nextId     = 0
local proxies    = setmetatable({}, { __mode = "k" })

local function nextFile()
  nextId = nextId + 1
  return SWAP_DIR .. "/s" .. nextId
end

function swap.init(modules)
  modules = modules or {}
  fs        = modules.fs        or fs
  serialize = modules.serialize or require("kernel.serialize")
  log       = modules.log
  config    = modules.config
  compress  = modules.compress or compress

  useCompress = (compress and compress.available and compress.available()) or false

  if not fs then return false, "fs module required" end

  if config and config.get then
    local m = config.get("swapMaxKB")
    if type(m) == "number" and m > 0 then maxBytes = math.floor(m) * 1024 end
  end

  if fs.spaceFree then
    local free = (fs.spaceFree(SWAP_DIR) or fs.spaceFree("/") or 0)
    local ceil = free - DISK_MARGIN
    if ceil < 0 then ceil = 0 end
    if maxBytes > ceil then maxBytes = ceil end
  end

  if not fs.exists(SWAP_DIR) then fs.makeDirectory(SWAP_DIR) end
  swap.clear()

  if log then
    log.info("swap", "Disk swap ready at " .. SWAP_DIR ..
      " (cap " .. math.floor(maxBytes / 1024) .. " KB" ..
      (useCompress and ", compressed" or "") .. ")")
  end
  return true
end

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

function swap.store(key, value)
  if not fs then return false, "swap not initialized" end
  if type(key) ~= "string" then return false, "key must be a string" end
  if value == nil then swap.free(key); return true end

  local ok, data = pcall(serialize.encode, value)
  if not ok then return false, "serialize failed: " .. tostring(data) end

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

function swap.fetch(key)
  if not fs then return nil end
  local e = entries[key]
  if not e then return nil end
  local data = fs.readFile(e.file)
  if not data then return nil end

  if useCompress and compress and compress.isPacked(data) then
    data = compress.unpack(data)
    if not data then return nil end
  end

  local v = serialize.decode(data, { maxBytes = maxBytes + 1024 })
  return v
end

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

function swap.usage()
  local count = 0
  for _ in pairs(entries) do count = count + 1 end
  return { bytes = totalBytes, count = count, max = maxBytes }
end

local function keyStr(ns, k)
  local t = type(k)
  if t == "number" then return ns .. "n" .. tostring(k) end
  if t == "string" then return ns .. "s" .. k end
  return nil
end

function swap.table(opts)
  opts = opts or {}
  local hotMax = tonumber(opts.hot) or LRU_DEFAULT
  if hotMax < 1 then hotMax = 1 end

  nextId = nextId + 1
  local ns = "t" .. nextId .. ":"

  local hot    = {}
  local order  = {}
  local keyset = {}

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
      if victim then hot[victim] = nil end
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

function swap.freeTable(proxy)
  local info = proxies[proxy]
  if not info then return false, "not a swap table" end
  for s in pairs(info.keyset) do swap.free(s) end
  proxies[proxy] = nil
  return true
end

swap.SWAP_DIR = SWAP_DIR

return swap
