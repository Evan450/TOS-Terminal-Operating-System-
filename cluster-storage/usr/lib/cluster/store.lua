

















local store = {}


local DEFAULT_TTL   = 3600     
local MAX_LEASE     = 86400    
local INDEX_NAME    = ".index"
local MAX_KEY       = 192      
local MAX_SEGMENTS  = 8


local fs, computer, serialize, log
local _root, _capacity
local _leaseSeq = 0
local _leaseFn                  






local _index = {}
local _used  = 0

function store.init(opts)
  opts       = opts or {}
  fs         = opts.fs or require("kernel.fs")
  computer   = opts.computer or require("computer")
  serialize  = opts.serialize or require("kernel.serialize")
  log        = opts.log or { info = function() end, warn = function() end,
                             error = function() end }
  _root      = (opts.root or "/var/cluster-store"):gsub("/+$", "")
  _capacity  = opts.capacity or 0        
  _leaseFn   = opts.leaseFn
  _index, _used, _leaseSeq = {}, 0, 0
  if fs.makeDirectory then pcall(fs.makeDirectory, _root) end
  store.loadIndex()
  return true
end

local function now() return computer and computer.uptime() or 0 end














function store.validateKey(key)
  if type(key) ~= "string" or key == "" then return nil, "invalid_key: empty" end
  if #key > MAX_KEY then return nil, "invalid_key: too long" end
  if key:sub(1, 1) == "/" then return nil, "invalid_key: absolute" end
  if key:sub(-1) == "/" then return nil, "invalid_key: trailing separator" end
  if key:find("//") then return nil, "invalid_key: empty segment" end
  local segs = {}
  for seg in key:gmatch("[^/]+") do
    if seg == ".." or seg == "." then return nil, "invalid_key: relative segment" end
    if not seg:match("^[%w_%-%.]+$") then
      return nil, "invalid_key: bad character in '" .. seg .. "'"
    end
    segs[#segs + 1] = seg
  end
  if #segs < 2 then return nil, "invalid_key: needs <namespace>/<path>" end
  if #segs > MAX_SEGMENTS then return nil, "invalid_key: too deep" end
  return segs
end

function store.pathFor(key)
  local segs, err = store.validateKey(key)
  if not segs then return nil, err end
  return _root .. "/" .. table.concat(segs, "/")
end





function store.indexPath() return _root .. "/" .. INDEX_NAME end

function store.saveIndex()
  if not (fs and serialize) then return false, "not_initialized" end
  local blob = serialize.encode({ index = _index, used = _used })
  local path, tmp = store.indexPath(), store.indexPath() .. ".tmp"
  
  
  
  local ok
  if fs.writeFile then ok = fs.writeFile(tmp, blob) else
    local h = fs.open(tmp, "w")
    if h then h:write(blob); h:close(); ok = true end
  end
  if not ok then return false, "write_failed: index" end
  if fs.exists and fs.exists(path) and fs.remove then pcall(fs.remove, path) end
  if fs.rename then
    local rok, rerr = fs.rename(tmp, path)
    if not rok then return false, "rename_failed: " .. tostring(rerr) end
  end
  return true
end

function store.loadIndex()
  _index, _used = {}, 0
  if not (fs and fs.exists and fs.exists(store.indexPath())) then return true, "cold_start" end
  local blob = fs.readFile and fs.readFile(store.indexPath())
  if not blob or blob == "" then return true, "cold_start" end
  local ok, decoded = pcall(serialize.decode, blob, { maxBytes = 65536 })
  if not ok or type(decoded) ~= "table" or type(decoded.index) ~= "table" then
    
    
    
    log.error("cluster.store", "index unreadable; refusing to run with an empty one")
    return false, "decode_failed: index"
  end
  _index = decoded.index
  _used = tonumber(decoded.used) or 0
  return true, "loaded"
end





function store.capacity()
  if _capacity and _capacity > 0 then return _capacity end
  if fs and fs.spaceTotal then return fs.spaceTotal(_root) or 0 end
  return 0
end

function store.used() return _used end
function store.free() return math.max(0, store.capacity() - _used) end





local function newLeaseId()
  if _leaseFn then return _leaseFn() end
  _leaseSeq = _leaseSeq + 1
  
  
  
  return string.format("%04x%02x", (math.floor(now() * 100) + _leaseSeq) % 0xFFFF,
                       _leaseSeq % 0xFF)
end

local function clampExpiry(base, seconds)
  local want = base + (seconds or DEFAULT_TTL)
  local ceiling = now() + MAX_LEASE
  return want > ceiling and ceiling or want
end















function store.evict(need)
  local reclaimed = 0
  local t = now()

  
  for key, rec in pairs(_index) do
    if rec.expires_at and rec.expires_at <= t then
      local sz = rec.size or 0
      if store._delete(key) then reclaimed = reclaimed + sz end
    end
  end
  if reclaimed >= (need or 0) then return reclaimed end

  
  
  local candidates = {}
  for key, rec in pairs(_index) do
    candidates[#candidates + 1] = { key = key, at = rec.last_access or rec.created or 0 }
  end
  table.sort(candidates, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.key < b.key                      
  end)
  for _, c in ipairs(candidates) do
    if reclaimed >= (need or 0) then break end
    local sz = (_index[c.key] or {}).size or 0
    if store._delete(c.key) then reclaimed = reclaimed + sz end
  end
  return reclaimed
end



function store._delete(key)
  local rec = _index[key]
  if not rec then return false end
  local path = store.pathFor(key)
  if path and fs.exists and fs.exists(path) then pcall(fs.remove, path) end
  _used = math.max(0, _used - (rec.size or 0))
  _index[key] = nil
  return true
end


function store.sweep()
  local t, n = now(), 0
  for key, rec in pairs(_index) do
    if rec.expires_at and rec.expires_at <= t then
      if store._delete(key) then n = n + 1 end
    end
  end
  if n > 0 then store.saveIndex() end
  return n
end






function store.put(key, data, opts)
  opts = opts or {}
  local path, err = store.pathFor(key)
  if not path then return nil, err end
  if type(data) ~= "string" then return nil, "invalid_data: not a string" end

  local existing = _index[key]
  if existing and opts.overwrite == false then
    return nil, "exists: " .. key
  end

  local size = #data
  local delta = size - ((existing and existing.size) or 0)
  if delta > store.free() then
    
    
    store.evict(delta - store.free())
    if delta > store.free() then
      return nil, "out_of_space: need " .. delta .. ", free " .. store.free()
    end
  end

  local dir = path:match("(.+)/[^/]+$")
  if dir and fs.makeDirectory then pcall(fs.makeDirectory, dir) end

  
  
  local tmp = path .. ".tmp"
  local wok
  if fs.writeFile then wok = fs.writeFile(tmp, data) else
    local h = fs.open(tmp, "w")
    if h then h:write(data); h:close(); wok = true end
  end
  if not wok then return nil, "write_failed: " .. key end
  if fs.exists and fs.exists(path) and fs.remove then pcall(fs.remove, path) end
  if fs.rename then
    local rok, rerr = fs.rename(tmp, path)
    if not rok then return nil, "rename_failed: " .. tostring(rerr) end
  end

  local t = now()
  local lease = (existing and opts.keep_lease) and existing.lease_id or newLeaseId()
  _index[key] = {
    lease_id    = lease,
    expires_at  = clampExpiry(t, opts.ttl and opts.ttl > 0 and opts.ttl or DEFAULT_TTL),
    size        = size,
    created     = (existing and existing.created) or t,
    last_access = t,
  }
  _used = _used + delta
  store.saveIndex()
  return {
    key = key, lease_id = lease,
    expires_at = _index[key].expires_at, size_bytes = size,
  }
end







function store.get(key)
  local path, err = store.pathFor(key)
  if not path then return nil, err end
  local rec = _index[key]
  if not rec then return nil, "no_such_key" end
  if not (fs.exists and fs.exists(path)) then
    
    _index[key] = nil
    _used = math.max(0, _used - (rec.size or 0))
    return nil, "no_such_key"
  end
  if not rec.expires_at or rec.expires_at > now() then
    rec.last_access = now()
  end
  local data = fs.readFile and fs.readFile(path)
  if data == nil then return nil, "read_failed: " .. key end
  return data
end

function store.exists(key) return _index[key] ~= nil end


function store.list(prefix, limit)
  prefix = prefix or ""
  local out = {}
  for key, rec in pairs(_index) do
    if key:sub(1, #prefix) == prefix then
      out[#out + 1] = { key = key, size = rec.size, expires_at = rec.expires_at }
    end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  if limit and #out > limit then
    local trimmed = {}
    for i = 1, limit do trimmed[i] = out[i] end
    return trimmed, true
  end
  return out, false
end



function store.extend(key, lease_id, seconds)
  local rec = _index[key]
  if not rec then return nil, "no_such_key" end
  if rec.lease_id ~= lease_id then return nil, "lease_mismatch" end
  rec.expires_at = clampExpiry(now(), seconds or DEFAULT_TTL)
  rec.last_access = now()
  store.saveIndex()
  return { key = key, expires_at = rec.expires_at }
end




function store.release(key, lease_id)
  local rec = _index[key]
  if not rec then return nil, "no_such_key" end
  if rec.lease_id ~= lease_id then return nil, "lease_mismatch" end
  store._delete(key)
  store.saveIndex()
  return { key = key, released = true }
end

function store.stats()
  local n = 0
  for _ in pairs(_index) do n = n + 1 end
  return {
    keys = n, used_bytes = _used,
    capacity_bytes = store.capacity(), free_bytes = store.free(),
    root = _root,
  }
end

store._internal = {
  DEFAULT_TTL = DEFAULT_TTL,
  MAX_LEASE   = MAX_LEASE,
  MAX_KEY     = MAX_KEY,
  index       = function() return _index end,
  setUsed     = function(v) _used = v end,
}

return store
