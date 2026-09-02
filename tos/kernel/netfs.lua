local netfs = {}

local BLOCK          = 4096
local RPC_TIMEOUT    = 10
local SPACE_TTL      = 30
local MAX_HANDLES    = 16
local HANDLE_IDLE    = 120
local MAX_PATH       = 256
local MAX_LIST       = 256

local net, fs, trustMgr, log, protocol, computer

function netfs.init(modules)
  modules  = modules or {}
  net      = modules.net
  fs       = modules.fs
  trustMgr = modules.trust
  log      = modules.log
  computer = modules.computer or require("computer")

  protocol = modules.protocol or (net and net.getProtocol and net.getProtocol())
  if not protocol then
    local okP, mod = pcall(require, "kernel.net.protocol")
    if okP then protocol = mod end
  end

  if net and protocol then
    net.on(protocol.TYPE.NETFS_REQ, function(packet, fromAddr)
      netfs.handleRequest(packet, fromAddr)
    end)
  end
  if log and log.info then log.info("netfs", "netfs module initialized") end
  return true
end

local enabled = false
function netfs.setEnabled(v) enabled = v and true or false end
function netfs.isEnabled()   return enabled end

netfs.EXPORTS_PATH = "/etc/netfs-exports.cfg"

local _exports = {}

function netfs._validateExports(cfg)
  if type(cfg) ~= "table" then return nil, "invalid_config: not a table" end
  local out, seen = {}, {}
  for i, e in ipairs(cfg) do
    local where = "entry " .. i
    if type(e) ~= "table" then return nil, "invalid_export: " .. where .. " not a table" end
    if type(e.name) ~= "string" or not e.name:match("^[%w_%-]+$") then
      return nil, "invalid_export: " .. where .. " needs a [%w_-] name"
    end
    if seen[e.name] then return nil, "invalid_export: duplicate name " .. e.name end
    if type(e.path) ~= "string" or e.path == "" then
      return nil, "invalid_export: " .. e.name .. " needs a path"
    end
    local mode = e.mode or "ro"
    if mode ~= "ro" and mode ~= "rw" then
      return nil, "invalid_export: " .. e.name .. " mode must be ro or rw"
    end
    if e.allow ~= nil and type(e.allow) ~= "table" then
      return nil, "invalid_export: " .. e.name .. " allow must be a list"
    end

    local root = fs and fs.normalize and fs.normalize(e.path) or e.path
    if type(root) ~= "string" or root == "" then
      return nil, "invalid_export: " .. e.name .. " path does not normalize"
    end
    root = root:gsub("/+$", "")
    if root == "" then root = "/" end

    if root == "/" then
      return nil, "invalid_export: " .. e.name .. " refuses to export /"
    end
    seen[e.name] = true
    out[#out + 1] = {
      name = e.name, path = root, mode = mode,
      allow = e.allow or {},
    }
  end
  return out
end

function netfs.setExports(list) _exports = list or {} end
function netfs.getExports()     return _exports end

function netfs.loadExports(fsModule, serializeMod)
  fsModule = fsModule or fs
  if not (fsModule and fsModule.exists and fsModule.exists(netfs.EXPORTS_PATH)) then
    _exports = {}
    return true, "no_exports"
  end
  local content = fsModule.readFile(netfs.EXPORTS_PATH)
  if not content or content == "" then _exports = {}; return true, "no_exports" end
  local ser = serializeMod or require("kernel.serialize")
  local ok, cfg = pcall(ser.decode, content, { maxBytes = 8192 })
  if not ok or type(cfg) ~= "table" then
    return false, "decode_failed: netfs-exports.cfg"
  end
  local list, err = netfs._validateExports(cfg)
  if not list then return false, err end
  _exports = list
  return true
end

function netfs._findExport(name)
  for _, e in ipairs(_exports) do
    if e.name == name then return e end
  end
  return nil
end

function netfs._accessOk(export, addr, wantWrite)
  if not export then return false, "no_such_export" end
  if wantWrite and export.mode ~= "rw" then return false, "read_only_export" end
  local allowed = false
  for _, entry in ipairs(export.allow) do
    if entry == addr then allowed = true; break end
    if entry == "*paired*" then

      if trustMgr and trustMgr.getLevel and trustMgr.LEVEL
         and trustMgr.getLevel(addr) >= trustMgr.LEVEL.TRUSTED then
        allowed = true; break
      end
    end
  end
  if not allowed then return false, "not_allowed" end
  return true
end

function netfs._confine(export, rel)
  if type(rel) ~= "string" or #rel > MAX_PATH then return nil, "invalid_path" end
  if rel == "" then rel = "/" end
  if rel:sub(1, 1) ~= "/" then rel = "/" .. rel end
  local abs = fs and fs.normalize and fs.normalize(export.path .. rel) or nil
  if type(abs) ~= "string" or abs == "" then return nil, "invalid_path" end
  if abs ~= export.path and abs:sub(1, #export.path + 1) ~= export.path .. "/" then
    return nil, "invalid_path"
  end
  return abs
end

local _handles = {}
local _nextHandle = 1

local function _reap(now)
  for addr, tbl in pairs(_handles) do
    for id, st in pairs(tbl) do
      if now - (st.last or 0) > HANDLE_IDLE then
        pcall(function() if st.h and st.h.close then st.h:close() end end)
        tbl[id] = nil
      end
    end
    if next(tbl) == nil then _handles[addr] = nil end
  end
end

local function _countHandles(addr)
  local n = 0
  for _ in pairs(_handles[addr] or {}) do n = n + 1 end
  return n
end

function netfs._dispatch(op, p, fromAddr)
  p = p or {}
  local now = computer and computer.uptime() or 0
  _reap(now)

  if op == "space" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, false)
    if not ok then return { err = err } end
    return {
      total = fs.spaceTotal and fs.spaceTotal(e.path) or 0,
      used  = fs.spaceUsed  and fs.spaceUsed(e.path)  or 0,
      read_only = e.mode ~= "rw",
    }
  end

  if op == "stat" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, false)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    if not fs.exists(abs) then return { exists = false } end
    return {
      exists = true,
      is_dir = fs.isDirectory(abs) and true or false,
      size   = fs.size and fs.size(abs) or 0,
      mtime  = fs.lastModified and fs.lastModified(abs) or 0,
    }
  end

  if op == "list" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, false)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    local items = fs.list(abs)
    if type(items) ~= "table" then return { entries = {} } end
    local out = {}
    for i = 1, math.min(#items, MAX_LIST) do out[i] = items[i] end
    return { entries = out, truncated = #items > MAX_LIST }
  end

  if op == "mkdir" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, true)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    return { ok = fs.makeDirectory(abs) and true or false }
  end

  if op == "remove" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, true)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    return { ok = fs.remove(abs) and true or false }
  end

  if op == "rename" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, true)
    if not ok then return { err = err } end

    local from, ferr = netfs._confine(e, p.path)
    if not from then return { err = ferr } end
    local to, terr = netfs._confine(e, p.to)
    if not to then return { err = terr } end
    return { ok = fs.rename(from, to) and true or false }
  end

  if op == "open" then
    local mode = p.mode or "r"
    local wantWrite = mode:find("[wa+]") ~= nil
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, wantWrite)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    if _countHandles(fromAddr) >= MAX_HANDLES then
      return { err = "too_many_handles" }
    end
    local h, oerr = fs.open(abs, mode)
    if not h then return { err = "open_failed: " .. tostring(oerr) } end
    local id = _nextHandle; _nextHandle = _nextHandle + 1
    _handles[fromAddr] = _handles[fromAddr] or {}
    _handles[fromAddr][id] = { h = h, export = e, mode = mode, last = now }
    return { handle_id = id }
  end

  local st = p.handle_id and _handles[fromAddr] and _handles[fromAddr][p.handle_id]

  if op == "read" then
    if not st then return { err = "no_such_handle" } end
    st.last = now
    local n = tonumber(p.n) or BLOCK
    if n > BLOCK then n = BLOCK end
    local chunk = st.h:read(n)
    if chunk == nil then return { eof = true } end
    return { data = chunk, eof = false }
  end

  if op == "write" then
    if not st then return { err = "no_such_handle" } end
    if st.export.mode ~= "rw" then return { err = "read_only_export" } end
    st.last = now
    local d = p.data
    if type(d) ~= "string" then return { err = "invalid_data" } end
    if #d > BLOCK then return { err = "chunk_too_large" } end
    local wok = st.h:write(d)
    return { ok = wok and true or false, written = #d }
  end

  if op == "close" then
    if not st then return { ok = true } end
    pcall(function() st.h:close() end)
    _handles[fromAddr][p.handle_id] = nil
    return { ok = true }
  end

  if op == "seek" then
    if not st then return { err = "no_such_handle" } end
    st.last = now
    return { pos = st.h:seek(p.whence or "set", tonumber(p.offset) or 0) }
  end

  return { err = "unknown_op" }
end

function netfs.handleRequest(packet, fromAddr)
  if not (net and protocol) then return end
  if not enabled then return end

  local function deny()

    local pkt = protocol.makePacket(protocol.TYPE.NETFS_RES,
      { req_id = packet and packet.payload and packet.payload.req_id,
        err = "denied" }, { to = fromAddr })
    net.send(fromAddr, pkt)
  end

  if not (trustMgr and trustMgr.getLevel and trustMgr.LEVEL) then return deny() end
  if trustMgr.getLevel(fromAddr) < trustMgr.LEVEL.TRUSTED then
    if log and log.warn then
      log.warn("netfs", "request from non-trusted peer " .. tostring(fromAddr):sub(1, 8))
    end
    return deny()
  end
  if net.verifyPeer then
    local vOk = net.verifyPeer(fromAddr)
    if not vOk then
      if log and log.warn then
        log.warn("netfs", "verification failed for " .. tostring(fromAddr):sub(1, 8))
      end
      return deny()
    end
  end

  local p = packet.payload or {}
  local reply = netfs._dispatch(p.op, p, fromAddr)
  reply.req_id = p.req_id
  net.send(fromAddr, protocol.makePacket(protocol.TYPE.NETFS_RES, reply,
    { to = fromAddr }))
end

local function _netTransport(hostAddr)
  local reqId = 0
  return function(op, payload)
    if not (net and protocol) then return nil, "no_network" end
    reqId = reqId + 1
    local myId = reqId
    payload.op = op
    payload.req_id = myId
    local got, res = false, nil
    local lid = net.on(protocol.TYPE.NETFS_RES, function(pkt, from)
      if from ~= hostAddr then return end
      local pl = pkt.payload or {}
      if pl.req_id ~= myId then return end
      got, res = true, pl
    end)
    local sent = net.send(hostAddr, protocol.makePacket(protocol.TYPE.NETFS_REQ,
      payload, { to = hostAddr }))
    if not sent then
      net.off(protocol.TYPE.NETFS_RES, lid)
      return nil, "send_failed"
    end
    net.waitFor(function() return got end, RPC_TIMEOUT)
    net.off(protocol.TYPE.NETFS_RES, lid)
    if not got then return nil, "timeout" end
    return res
  end
end

function netfs.attach(hostAddr, share, opts)
  opts = opts or {}
  local rpc = opts.transport or _netTransport(hostAddr)
  local proxy = {}

  proxy.address = "netfs:" .. tostring(hostAddr):sub(1, 8) .. ":" .. tostring(share)
  function proxy.getLabel() return "netfs(" .. tostring(share) .. ")" end

  local function call(op, payload)
    payload = payload or {}
    payload.share = share
    local res, err = rpc(op, payload)
    if not res then return nil, err or "no_reply" end
    if res.err then return nil, res.err end
    return res
  end
  proxy._call = call

  local spaceAt, spaceVal = -math.huge, nil
  local function space()
    local now = computer and computer.uptime() or 0
    if spaceVal and (now - spaceAt) < SPACE_TTL then return spaceVal end
    local res = call("space")
    if res then spaceVal = res; spaceAt = now end
    return spaceVal
  end
  function proxy.spaceTotal() local s = space(); return s and s.total or 0 end
  function proxy.spaceUsed()  local s = space(); return s and s.used  or 0 end
  function proxy.isReadOnly() local s = space(); return s and s.read_only or false end

  local function stat(rel)
    local res = call("stat", { path = rel })
    return res
  end
  function proxy.exists(rel)       local s = stat(rel); return s ~= nil and s.exists == true end
  function proxy.isDirectory(rel)  local s = stat(rel); return s ~= nil and s.is_dir == true end
  function proxy.size(rel)         local s = stat(rel); return s and s.size or 0 end
  function proxy.lastModified(rel) local s = stat(rel); return s and s.mtime or 0 end

  function proxy.list(rel)
    local res = call("list", { path = rel })
    return res and res.entries or {}
  end
  function proxy.makeDirectory(rel)
    local res = call("mkdir", { path = rel }); return res ~= nil and res.ok == true
  end
  function proxy.remove(rel)
    local res = call("remove", { path = rel }); return res ~= nil and res.ok == true
  end
  function proxy.rename(from, to)
    local res = call("rename", { path = from, to = to })
    if not res then return false end
    return res.ok == true
  end

  local handles, nextLocal = {}, 1

  function proxy.open(rel, mode)
    mode = mode or "r"
    local res, err = call("open", { path = rel, mode = mode })
    if not res then return nil, err end
    local id = nextLocal; nextLocal = nextLocal + 1
    handles[id] = {
      remote = res.handle_id, mode = mode,
      buf = "", pos = 1, eof = false,
      wbuf = {}, wlen = 0,
    }
    return id
  end

  function proxy.read(id, n)
    local st = handles[id]; if not st then return nil end
    n = tonumber(n) or BLOCK
    while (#st.buf - st.pos + 1) < n and not st.eof do
      local res = call("read", { handle_id = st.remote, n = BLOCK })
      if not res or res.eof or not res.data then st.eof = true; break end

      st.buf = st.buf:sub(st.pos) .. res.data
      st.pos = 1
    end
    local avail = #st.buf - st.pos + 1
    if avail <= 0 then return nil end
    local take = n < avail and n or avail
    local out = st.buf:sub(st.pos, st.pos + take - 1)
    st.pos = st.pos + take
    return out
  end

  local function flush(st)
    if st.wlen == 0 then return true end
    local blob = table.concat(st.wbuf)
    st.wbuf, st.wlen = {}, 0
    while #blob > 0 do
      local piece = blob:sub(1, BLOCK)
      blob = blob:sub(BLOCK + 1)
      local res = call("write", { handle_id = st.remote, data = piece })
      if not res or res.ok ~= true then return false end
    end
    return true
  end

  function proxy.write(id, d)
    local st = handles[id]; if not st then return false end
    if type(d) ~= "string" then return false end
    st.wbuf[#st.wbuf + 1] = d
    st.wlen = st.wlen + #d
    if st.wlen >= BLOCK then return flush(st) end
    return true
  end

  function proxy.close(id)
    local st = handles[id]; if not st then return true end
    local ok = flush(st)
    call("close", { handle_id = st.remote })
    handles[id] = nil
    return ok
  end

  function proxy.seek(id, whence, offset)
    local st = handles[id]; if not st then return nil end
    flush(st)
    local res = call("seek", { handle_id = st.remote, whence = whence, offset = offset })

    st.buf, st.pos, st.eof = "", 1, false
    return res and res.pos or nil
  end

  return proxy
end

netfs._internal = {
  BLOCK       = BLOCK,
  MAX_HANDLES = MAX_HANDLES,
  MAX_LIST    = MAX_LIST,
  HANDLE_IDLE = HANDLE_IDLE,
  handles     = function() return _handles end,
  resetHandles = function() _handles = {}; _nextHandle = 1 end,
}

return netfs
